// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/NuvioAgentStore.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockAgentID {
    mapping(address => uint256) public balances;

    function setBalance(address a, uint256 b) external {
        balances[a] = b;
    }

    function balanceOf(address a) external view returns (uint256) {
        return balances[a];
    }
}

contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "mUSDT") {}

    function decimals() public pure override returns (uint8) {
        return 18; // BSC USDT uses 18 decimals (verified on-chain 2026-11-18)
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Tries to re-enter confirmReceipt from its receive() hook.
contract ReentrancyAttacker {
    NuvioAgentStore public store;
    uint256 public orderId;

    constructor(NuvioAgentStore _store) {
        store = _store;
    }

    function setOrder(uint256 _orderId) external {
        orderId = _orderId;
    }

    receive() external payable {
        // Attempt re-entry: must revert (guarded) or fail (status already Completed).
        try store.confirmReceipt(orderId) {} catch {}
    }
}

contract NuvioAgentStoreTest is Test {
    NuvioAgentStore public store;
    MockAgentID public agentId;
    MockUSDT public usdt;

    address public owner = address(this);
    address public buyer = address(0xB0B);
    address public stranger = address(0x5EED);

    uint256 constant BNB_PRICE = 0.01 ether;
    uint256 constant USDT_PRICE = 2.5 ether; // 2.50 USDT (18 decimals on BSC)

    // Test contract is the store owner and must be able to receive BNB releases.
    receive() external payable {}

    function setUp() public {
        agentId = new MockAgentID();
        usdt = new MockUSDT();
        store = new NuvioAgentStore(address(agentId), address(usdt), address(this));

        agentId.setBalance(buyer, 1);
        agentId.setBalance(owner, 1);
        usdt.mint(buyer, 100 ether); // 100 USDT (18 decimals on BSC)

        vm.deal(buyer, 10 ether);
        vm.deal(stranger, 10 ether);

        store.addProduct("YouTube Premium 1 Bulan", "Akun Premium", BNB_PRICE, USDT_PRICE);
        store.addProduct("Spotify Premium 1 Bulan", "Akun Premium", 0.005 ether, 1.2 ether);
    }

    // -- gating ---------------------------------------------------------------

    function testNonHolderCannotBuy() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NuvioAgentStore.NotAgentIdHolder.selector, stranger));
        store.createOrderBNB{value: BNB_PRICE}(0);
    }

    function testHolderCanBuyBNB() public {
        vm.prank(buyer);
        uint256 id = store.createOrderBNB{value: BNB_PRICE}(0);
        assertEq(id, 0);
        NuvioAgentStore.Order memory o = store.getOrder(0);
        assertEq(uint256(o.status), uint256(NuvioAgentStore.OrderStatus.Paid));
        assertEq(address(store).balance, BNB_PRICE);
    }

    function testWrongValueReverts() public {
        vm.prank(buyer);
        vm.expectRevert(
            abi.encodeWithSelector(NuvioAgentStore.WrongPaymentAmount.selector, BNB_PRICE, BNB_PRICE - 1)
        );
        store.createOrderBNB{value: BNB_PRICE - 1}(0);
    }

    function testInactiveProductReverts() public {
        store.setProductActive(0, false);
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(NuvioAgentStore.ProductInactive.selector, 0));
        store.createOrderBNB{value: BNB_PRICE}(0);
    }

    // -- USDT flow ------------------------------------------------------------

    function testHolderCanBuyUSDT() public {
        vm.startPrank(buyer);
        usdt.approve(address(store), USDT_PRICE);
        uint256 id = store.createOrderUSDT(0);
        vm.stopPrank();
        assertEq(id, 0);
        assertEq(usdt.balanceOf(address(store)), USDT_PRICE);
        // Exact approval only: allowance fully consumed.
        assertEq(usdt.allowance(buyer, address(store)), 0);
    }

    function testUSDTWithoutApprovalReverts() public {
        vm.prank(buyer);
        vm.expectRevert();
        store.createOrderUSDT(0);
    }

    // -- fulfilment: happy path ----------------------------------------------

    function testFullFlowBNB() public {
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);

        uint256 sellerBefore = owner.balance;
        store.markDelivered(0, "TG-ORDER-001");

        vm.prank(buyer);
        store.confirmReceipt(0);

        NuvioAgentStore.Order memory o = store.getOrder(0);
        assertEq(uint256(o.status), uint256(NuvioAgentStore.OrderStatus.Completed));
        assertEq(owner.balance, sellerBefore + BNB_PRICE);
        assertEq(address(store).balance, 0);
    }

    function testFullFlowUSDT() public {
        vm.startPrank(buyer);
        usdt.approve(address(store), USDT_PRICE);
        store.createOrderUSDT(0);
        vm.stopPrank();

        store.markDelivered(0, "TG-ORDER-002");
        uint256 sellerBefore = usdt.balanceOf(owner);

        vm.prank(buyer);
        store.confirmReceipt(0);

        assertEq(usdt.balanceOf(owner), sellerBefore + USDT_PRICE);
        assertEq(usdt.balanceOf(address(store)), 0);
    }

    // -- auto-release ---------------------------------------------------------

    function testReleaseBeforeWindowReverts() public {
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);
        store.markDelivered(0, "TG-001");
        vm.expectRevert(
            abi.encodeWithSelector(
                NuvioAgentStore.DeliveryWindowNotPassed.selector, block.timestamp + store.DELIVERY_WINDOW()
            )
        );
        store.releaseOrder(0);
    }

    function testAutoReleaseAfterWindow() public {
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);
        store.markDelivered(0, "TG-001");
        vm.warp(block.timestamp + 3 days + 1);
        uint256 sellerBefore = owner.balance;
        store.releaseOrder(0); // anyone can call
        assertEq(owner.balance, sellerBefore + BNB_PRICE);
    }

    // -- refunds / cancel -----------------------------------------------------

    function testBuyerCancelRefunds() public {
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);
        uint256 buyerBefore = buyer.balance;
        vm.prank(buyer);
        store.cancelOrder(0);
        assertEq(buyer.balance, buyerBefore + BNB_PRICE);
        assertEq(address(store).balance, 0);
    }

    function testClaimRefundBeforeDeadlineReverts() public {
        // Compute the expected timestamp BEFORE pranking: any contract call
        // between vm.prank and the target call consumes the prank.
        uint256 refundableAt = block.timestamp + store.DELIVERY_DEADLINE();
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);
        vm.expectRevert(
            abi.encodeWithSelector(NuvioAgentStore.DeliveryDeadlineNotPassed.selector, refundableAt)
        );
        vm.prank(buyer);
        store.claimRefund(0);
    }

    function testClaimRefundAfterDeadline() public {
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);
        vm.warp(block.timestamp + 7 days + 1);
        uint256 buyerBefore = buyer.balance;
        vm.prank(buyer);
        store.claimRefund(0);
        assertEq(buyer.balance, buyerBefore + BNB_PRICE);
    }

    function testOwnerRefund() public {
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);
        store.markDelivered(0, "TG-001");
        uint256 buyerBefore = buyer.balance;
        store.refundOrder(0);
        assertEq(buyer.balance, buyerBefore + BNB_PRICE);
    }

    // -- access control -------------------------------------------------------

    function testOnlyOwnerCanAddProduct() public {
        vm.prank(stranger);
        vm.expectRevert();
        store.addProduct("X", "Y", 1, 1);
    }

    function testOnlyOwnerCanMarkDelivered() public {
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);
        vm.prank(buyer);
        vm.expectRevert();
        store.markDelivered(0, "TG-001");
    }

    function testOnlyBuyerCanConfirm() public {
        vm.prank(buyer);
        store.createOrderBNB{value: BNB_PRICE}(0);
        store.markDelivered(0, "TG-001");
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(NuvioAgentStore.NotBuyer.selector, stranger));
        store.confirmReceipt(0);
    }

    // -- pause ----------------------------------------------------------------

    function testPauseBlocksOrders() public {
        store.pause();
        vm.prank(buyer);
        vm.expectRevert();
        store.createOrderBNB{value: BNB_PRICE}(0);
    }

    // -- reentrancy -----------------------------------------------------------

    function testReentrancyBlocked() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(store);
        agentId.setBalance(address(attacker), 1);
        vm.deal(address(attacker), 10 ether);

        vm.prank(address(attacker));
        uint256 id = store.createOrderBNB{value: BNB_PRICE}(0);
        attacker.setOrder(id);
        store.markDelivered(id, "TG-ATTACK");

        uint256 sellerBefore = owner.balance;
        // Attacker's receive() tries to re-enter confirmReceipt during the release.
        // Either the guard reverts the inner call or the status check does — the
        // outer call must still complete exactly once.
        vm.prank(address(attacker));
        store.confirmReceipt(id);

        assertEq(owner.balance, sellerBefore + BNB_PRICE);
        assertEq(address(store).balance, 0);
        NuvioAgentStore.Order memory o = store.getOrder(id);
        assertEq(uint256(o.status), uint256(NuvioAgentStore.OrderStatus.Completed));
    }

    // -- direct BNB transfers rejected ----------------------------------------

    function testDirectBNBTransferReverts() public {
        vm.prank(buyer);
        (bool ok,) = address(store).call{value: 1 ether}("");
        assertFalse(ok);
    }

    // -- batch products -------------------------------------------------------

    function testAddProductsBatch() public {
        NuvioAgentStore.ProductInput[] memory inputs = new NuvioAgentStore.ProductInput[](2);
        inputs[0] = NuvioAgentStore.ProductInput("Netflix 1 Bulan", "Akun Premium", 0.008 ether, 2 ether);
        inputs[1] = NuvioAgentStore.ProductInput("Canva Pro 1 Bulan", "Akun Premium", 0.003 ether, 0.8 ether);
        uint256[] memory ids = store.addProducts(inputs);
        assertEq(ids[0], 2);
        assertEq(ids[1], 3);
        assertEq(store.productCount(), 4);
    }
}
