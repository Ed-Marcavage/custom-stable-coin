import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {Vm} from "forge-std/Vm.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DCSCoinTest is Test {
    DeployDecentralizedStableCoin deployDecentralizedStableCoin;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    function setUp() external {
        // @todo - understand this better
        deployDecentralizedStableCoin = new DeployDecentralizedStableCoin();
        (dsc, dsce, config) = deployDecentralizedStableCoin.run();
        (ethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();

        // ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        // ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    function testNameIsCorrect() public {
        assertEq(dsc.name(), "DecentralizedStableCoin");
    }

    function testSymbolIsCorrect() public {
        assertEq(dsc.symbol(), "DSC");
    }

    modifier mintDsc() {
        vm.startPrank(address(dsce));
        dsc.mint(address(dsce), 100);
        vm.stopPrank();
        _;
    }

    function testMint() public mintDsc {
        assertEq(dsc.balanceOf(address(dsce)), 100);
    }

    function testBurn() public mintDsc {
        vm.startPrank(address(dsce));
        dsc.burn(100);
        assertEq(dsc.balanceOf(address(dsce)), 0);
        vm.stopPrank();
    }

    function testBurnMustBeMoreThanZero() public {
        vm.startPrank(address(dsce));
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__AmountMustBeMoreThanZero
                .selector
        );
        dsc.burn(0);
        vm.stopPrank();
    }

    function testExceedsDscBalance() public {
        vm.startPrank(address(dsce));
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__BurnAmountExceedsBalance
                .selector
        );
        dsc.burn(1);
        vm.stopPrank();
    }

    function testBurnOnlyOwner() public {
        vm.startPrank(address(this));
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.burn(1);
        vm.stopPrank();
    }

    function testMintMustBeMoreThanZero() public {
        vm.startPrank(address(dsce));
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__AmountMustBeMoreThanZero
                .selector
        );
        dsc.mint(address(dsce), 0);
        vm.stopPrank();
    }

    function testMintZeroAddress() public {
        vm.startPrank(address(dsce));
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__NotZeroAddress
                .selector
        );
        dsc.mint(address(0), 1);
        vm.stopPrank();
    }

    function testMintOnlyOwner() public {
        vm.startPrank(address(this));
        vm.expectRevert("Ownable: caller is not the owner");
        dsc.mint(address(this), 1);
        vm.stopPrank();
    }

    //@todo start here
    function testCanBurnAnyonesTokens() public mintDsc {
        address USER = makeAddr("user");
        uint256 amountCollateral = 10 ether;
        uint256 amountToMint = 100 ether;

        // First User Mints DSC thru dsce
        vm.startPrank(USER);
        ERC20Mock(weth).mint(USER, amountCollateral);
        ERC20Mock(weth).approve(address(dsce), amountCollateral);
        dsce.depositCollateralAndMintDSC(weth, amountCollateral, amountToMint);
        vm.stopPrank();

        // Then anyone can burn the DSC thru burnFrom function
        vm.startPrank(USER);
        dsc.approve(USER, amountToMint);
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin__BlockFunction
                .selector
        );
        dsc.burnFrom(USER, amountToMint);
        vm.stopPrank();
    }
}
