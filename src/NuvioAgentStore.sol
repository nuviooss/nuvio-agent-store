// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title NuvioAgentStore
/// @author NUVIO (nuvio.ai)
/// @notice On-chain digital-goods store on BNB Chain for the Binance Agent ID Hackathon.
/// @dev Only Binance Agent ID holders (ERC-721 balanceOf > 0 on the official Agent ID
/// contract) can buy. Payments are held in escrow in this contract until the buyer
/// confirms receipt, the auto-release window passes, or a refund is issued.
/// Delivery of the digital good itself (account credentials / service fulfilment)
/// happens off-chain via the NUVIO Telegram store; the seller records a delivery
/// reference on-chain when marking an order delivered.
///
/// OWNER PERMISSIONS (disclosed, per hackathon rules):
///  - addProduct / updateProduct / setProductActive: manage the catalogue and prices.
///  - markDelivered: record that an order was fulfilled off-chain (with a ref).
///  - refundOrder: goodwill refund of an order that is Paid or Delivered.
///  - setAgentId: point at a new official Agent ID contract ONLY if Binance migrates it.
///  - pause / unpause: halt new orders in an emergency.
///  - transferOwnership: standard two-step ownership transfer (Ownable).
/// The owner CANNOT: withdraw escrowed funds except via a Completed order (release
/// happens only through confirmReceipt / releaseOrder / refund flows), mint tokens,
/// change prices of already-paid orders, or move a buyer's funds to any address
/// other than the seller (on completion) or the buyer (on refund/cancel).
interface IAgentID {
    function balanceOf(address account) external view returns (uint256);
}

contract NuvioAgentStore is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Official Binance Agent ID contract (SPACE ID Agent ID, ERC-721, non-transferable).
    IAgentID public agentId;

    /// @notice USDT (BEP-20) on BNB Chain.
    IERC20 public immutable usdt;

    /// @notice Seconds after delivery before anyone may auto-release escrow to the seller.
    uint256 public constant DELIVERY_WINDOW = 3 days;

    /// @notice Seconds after payment within which the seller must deliver, else buyer may claim a refund.
    uint256 public constant DELIVERY_DEADLINE = 7 days;

    enum PayToken {
        BNB,
        USDT
    }

    enum OrderStatus {
        Paid,
        Delivered,
        Completed,
        Refunded,
        Cancelled
    }

    struct Product {
        uint256 id;
        string name;
        string category;
        uint256 priceBNB; // in wei, 0 = not sold in BNB
        uint256 priceUSDT; // in USDT smallest unit (6 decimals), 0 = not sold in USDT
        bool active;
    }

    struct ProductInput {
        string name;
        string category;
        uint256 priceBNB;
        uint256 priceUSDT;
    }

    struct Order {
        uint256 id;
        address buyer;
        uint256 productId;
        PayToken payToken;
        uint256 amount;
        OrderStatus status;
        uint256 paidAt;
        uint256 deliveredAt;
        string deliveryRef;
    }

    uint256 public productCount;
    uint256 public orderCount;

    mapping(uint256 => Product) public products;
    mapping(uint256 => Order) public orders;

    event ProductAdded(uint256 indexed productId, string name, uint256 priceBNB, uint256 priceUSDT);
    event ProductUpdated(uint256 indexed productId, uint256 priceBNB, uint256 priceUSDT, bool active);
    event OrderCreated(
        uint256 indexed orderId, address indexed buyer, uint256 indexed productId, PayToken payToken, uint256 amount
    );
    event OrderDelivered(uint256 indexed orderId, string deliveryRef);
    event OrderCompleted(uint256 indexed orderId, address indexed seller, uint256 amount);
    event OrderRefunded(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event OrderCancelled(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event AgentIdUpdated(address indexed oldAgentId, address indexed newAgentId);

    error NotAgentIdHolder(address account);
    error ProductNotFound(uint256 productId);
    error ProductInactive(uint256 productId);
    error NotPricedInToken(uint256 productId);
    error WrongPaymentAmount(uint256 expected, uint256 received);
    error OrderNotFound(uint256 orderId);
    error NotBuyer(address caller);
    error InvalidStatus(OrderStatus current, OrderStatus expected);
    error DeliveryWindowNotPassed(uint256 releasableAt);
    error DeliveryDeadlineNotPassed(uint256 refundableAt);
    error EmptyName();
    error ZeroAddress();

    /// @param agentId_ Official Binance Agent ID contract address.
    /// @param usdt_ USDT (BEP-20) contract address on BNB Chain.
    /// @param owner_ Owner of the store (receives released escrow, manages catalogue).
    /// @dev `owner_` is explicit (instead of msg.sender) so the store can be deployed
    /// through a CREATE2 factory, where msg.sender would otherwise be the factory.
    constructor(address agentId_, address usdt_, address owner_) Ownable(owner_) {
        if (agentId_ == address(0) || usdt_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        agentId = IAgentID(agentId_);
        usdt = IERC20(usdt_);
    }

    // ------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------

    /// @notice True when `account` holds at least one Agent ID.
    function hasAgentId(address account) public view returns (bool) {
        return agentId.balanceOf(account) > 0;
    }

    function getProduct(uint256 productId) external view returns (Product memory) {
        if (productId >= productCount) revert ProductNotFound(productId);
        return products[productId];
    }

    function getOrder(uint256 orderId) external view returns (Order memory) {
        if (orderId >= orderCount) revert OrderNotFound(orderId);
        return orders[orderId];
    }

    // ------------------------------------------------------------------------
    // Catalogue (owner only)
    // ------------------------------------------------------------------------

    /// @notice Add one product to the catalogue.
    function addProduct(string calldata name, string calldata category, uint256 priceBNB, uint256 priceUSDT)
        public
        onlyOwner
        returns (uint256 productId)
    {
        if (bytes(name).length == 0) revert EmptyName();
        productId = productCount++;
        products[productId] = Product({
            id: productId,
            name: name,
            category: category,
            priceBNB: priceBNB,
            priceUSDT: priceUSDT,
            active: true
        });
        emit ProductAdded(productId, name, priceBNB, priceUSDT);
    }

    /// @notice Add several products in a single transaction (saves gas vs one tx each).
    function addProducts(ProductInput[] calldata inputs) external onlyOwner returns (uint256[] memory ids) {
        ids = new uint256[](inputs.length);
        for (uint256 i = 0; i < inputs.length; i++) {
            ids[i] = addProduct(inputs[i].name, inputs[i].category, inputs[i].priceBNB, inputs[i].priceUSDT);
        }
    }

    /// @notice Change a product's prices. Does not affect already-paid orders.
    function updateProduct(uint256 productId, uint256 priceBNB, uint256 priceUSDT) external onlyOwner {
        if (productId >= productCount) revert ProductNotFound(productId);
        products[productId].priceBNB = priceBNB;
        products[productId].priceUSDT = priceUSDT;
        emit ProductUpdated(productId, priceBNB, priceUSDT, products[productId].active);
    }

    /// @notice Activate / deactivate a product.
    function setProductActive(uint256 productId, bool active) external onlyOwner {
        if (productId >= productCount) revert ProductNotFound(productId);
        products[productId].active = active;
        emit ProductUpdated(productId, products[productId].priceBNB, products[productId].priceUSDT, active);
    }

    /// @notice Point at a new Agent ID contract if Binance ever migrates it.
    function setAgentId(address agentId_) external onlyOwner {
        if (agentId_ == address(0)) revert ZeroAddress();
        address old = address(agentId);
        agentId = IAgentID(agentId_);
        emit AgentIdUpdated(old, agentId_);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ------------------------------------------------------------------------
    // Buying (Agent ID holders only)
    // ------------------------------------------------------------------------

    modifier onlyAgentIdHolder() {
        if (!hasAgentId(msg.sender)) revert NotAgentIdHolder(msg.sender);
        _;
    }

    /// @notice Buy a product with BNB. Exact payment required; funds are escrowed here.
    function createOrderBNB(uint256 productId)
        external
        payable
        nonReentrant
        whenNotPaused
        onlyAgentIdHolder
        returns (uint256 orderId)
    {
        Product memory p = _activeProduct(productId);
        if (p.priceBNB == 0) revert NotPricedInToken(productId);
        if (msg.value != p.priceBNB) revert WrongPaymentAmount(p.priceBNB, msg.value);

        orderId = orderCount++;
        orders[orderId] = Order({
            id: orderId,
            buyer: msg.sender,
            productId: productId,
            payToken: PayToken.BNB,
            amount: msg.value,
            status: OrderStatus.Paid,
            paidAt: block.timestamp,
            deliveredAt: 0,
            deliveryRef: ""
        });
        emit OrderCreated(orderId, msg.sender, productId, PayToken.BNB, msg.value);
    }

    /// @notice Buy a product with USDT. Buyer must approve exactly `priceUSDT` first
    /// (no unlimited approvals — approve the exact order amount only).
    function createOrderUSDT(uint256 productId)
        external
        nonReentrant
        whenNotPaused
        onlyAgentIdHolder
        returns (uint256 orderId)
    {
        Product memory p = _activeProduct(productId);
        if (p.priceUSDT == 0) revert NotPricedInToken(productId);

        orderId = orderCount++;
        orders[orderId] = Order({
            id: orderId,
            buyer: msg.sender,
            productId: productId,
            payToken: PayToken.USDT,
            amount: p.priceUSDT,
            status: OrderStatus.Paid,
            paidAt: block.timestamp,
            deliveredAt: 0,
            deliveryRef: ""
        });
        // EFFECTS (order recorded) before INTERACTION (token pull) — CEI pattern.
        usdt.safeTransferFrom(msg.sender, address(this), p.priceUSDT);
        emit OrderCreated(orderId, msg.sender, productId, PayToken.USDT, p.priceUSDT);
    }

    // ------------------------------------------------------------------------
    // Fulfilment
    // ------------------------------------------------------------------------

    /// @notice Seller records off-chain delivery (e.g. Telegram order reference).
    function markDelivered(uint256 orderId, string calldata deliveryRef) external onlyOwner {
        Order storage o = _paidOrder(orderId);
        o.status = OrderStatus.Delivered;
        o.deliveredAt = block.timestamp;
        o.deliveryRef = deliveryRef;
        emit OrderDelivered(orderId, deliveryRef);
    }

    /// @notice Buyer confirms receipt; escrow is released to the seller (owner).
    function confirmReceipt(uint256 orderId) external nonReentrant {
        Order storage o = _order(orderId);
        if (o.buyer != msg.sender) revert NotBuyer(msg.sender);
        if (o.status != OrderStatus.Delivered) revert InvalidStatus(o.status, OrderStatus.Delivered);
        o.status = OrderStatus.Completed;
        _release(o);
        emit OrderCompleted(orderId, owner(), o.amount);
    }

    /// @notice Anyone may release escrow to the seller once the delivery window passed
    /// without a buyer dispute, so funds never get stuck if the buyer goes silent.
    function releaseOrder(uint256 orderId) external nonReentrant {
        Order storage o = _order(orderId);
        if (o.status != OrderStatus.Delivered) revert InvalidStatus(o.status, OrderStatus.Delivered);
        if (block.timestamp < o.deliveredAt + DELIVERY_WINDOW) {
            revert DeliveryWindowNotPassed(o.deliveredAt + DELIVERY_WINDOW);
        }
        o.status = OrderStatus.Completed;
        _release(o);
        emit OrderCompleted(orderId, owner(), o.amount);
    }

    /// @notice Buyer cancels an undelivered order; escrow is refunded in full.
    function cancelOrder(uint256 orderId) external nonReentrant {
        Order storage o = _order(orderId);
        if (o.buyer != msg.sender) revert NotBuyer(msg.sender);
        if (o.status != OrderStatus.Paid) revert InvalidStatus(o.status, OrderStatus.Paid);
        o.status = OrderStatus.Cancelled;
        _refund(o);
        emit OrderCancelled(orderId, msg.sender, o.amount);
    }

    /// @notice Buyer claims a refund when the seller never delivered within the deadline.
    function claimRefund(uint256 orderId) external nonReentrant {
        Order storage o = _order(orderId);
        if (o.buyer != msg.sender) revert NotBuyer(msg.sender);
        if (o.status != OrderStatus.Paid) revert InvalidStatus(o.status, OrderStatus.Paid);
        if (block.timestamp < o.paidAt + DELIVERY_DEADLINE) {
            revert DeliveryDeadlineNotPassed(o.paidAt + DELIVERY_DEADLINE);
        }
        o.status = OrderStatus.Refunded;
        _refund(o);
        emit OrderRefunded(orderId, msg.sender, o.amount);
    }

    /// @notice Owner goodwill refund of a Paid or Delivered order.
    function refundOrder(uint256 orderId) external onlyOwner nonReentrant {
        Order storage o = _order(orderId);
        if (o.status != OrderStatus.Paid && o.status != OrderStatus.Delivered) {
            revert InvalidStatus(o.status, OrderStatus.Paid);
        }
        o.status = OrderStatus.Refunded;
        _refund(o);
        emit OrderRefunded(orderId, o.buyer, o.amount);
    }

    // ------------------------------------------------------------------------
    // Internal
    // ------------------------------------------------------------------------

    function _activeProduct(uint256 productId) internal view returns (Product memory p) {
        if (productId >= productCount) revert ProductNotFound(productId);
        p = products[productId];
        if (!p.active) revert ProductInactive(productId);
    }

    function _order(uint256 orderId) internal view returns (Order storage) {
        if (orderId >= orderCount) revert OrderNotFound(orderId);
        return orders[orderId];
    }

    function _paidOrder(uint256 orderId) internal view returns (Order storage o) {
        o = _order(orderId);
        if (o.status != OrderStatus.Paid) revert InvalidStatus(o.status, OrderStatus.Paid);
    }

    function _release(Order storage o) internal {
        if (o.payToken == PayToken.BNB) {
            (bool ok,) = payable(owner()).call{value: o.amount}("");
            require(ok, "BNB release failed");
        } else {
            usdt.safeTransfer(owner(), o.amount);
        }
    }

    function _refund(Order storage o) internal {
        if (o.payToken == PayToken.BNB) {
            (bool ok,) = payable(o.buyer).call{value: o.amount}("");
            require(ok, "BNB refund failed");
        } else {
            usdt.safeTransfer(o.buyer, o.amount);
        }
    }

    /// @notice The contract only accepts BNB as payment through createOrderBNB.
    receive() external payable {
        revert("Use createOrderBNB");
    }
}
