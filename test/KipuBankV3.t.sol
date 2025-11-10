//cat out/KipuBankV3.sol/KipuBankV3.json | jq '.abi'
//Para ver el abi por consola en formato json

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {KipuBankV3} from "../src/KipuBankV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract KipuBankV3Test is Test {
    KipuBankV3 public banco;
    
    // Addresses de Sepolia
    address constant USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant WETH_SEPOLIA = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
    address constant ROUTER_SEPOLIA = 0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008;
    
    // Parámetros del banco
    uint256 constant BANK_CAP = 1000 * 10**6;  // $1000
    uint256 constant UMBRAL_RETIRO = 100 * 10**6;  // $100
    
    // Usuarios de prueba
    address public owner;
    address public user1;
    address public user2;
    
    // Fork de Sepolia
    uint256 public sepoliaFork;
    
    function setUp() public {
        // Crear fork de Sepolia para tests realistas
        string memory SEPOLIA_RPC = vm.envString("SEPOLIA_RPC_URL");
        sepoliaFork = vm.createFork(SEPOLIA_RPC);
        vm.selectFork(sepoliaFork);
        
        // Setup usuarios
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy contrato
        vm.prank(owner);
        banco = new KipuBankV3(
            BANK_CAP,
            UMBRAL_RETIRO,
            USDC_SEPOLIA,
            WETH_SEPOLIA,
            owner,
            ROUTER_SEPOLIA
        );
        
        // Dar ETH a usuarios para tests
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                        TESTS DE DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    
    function test_DeploymentConfiguracionCorrecta() public view {
        assertEq(banco.owner(), owner);
        assertEq(banco.i_bankCapUSD(), BANK_CAP);
        assertEq(banco.getUmbralRetiro(), UMBRAL_RETIRO);
        assertEq(address(banco.i_usdc()), USDC_SEPOLIA);
        assertEq(address(banco.i_weth()), WETH_SEPOLIA);
    }
    
    function test_EstadoInicialDelBanco() public view {
        assertEq(banco.s_totalDepositadoUSD(), 0);
        assertEq(banco.s_contadorDepositos(), 0);
        assertEq(banco.s_contadorRetiros(), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        TESTS DE DEPOSITOS ETH
    //////////////////////////////////////////////////////////////*/
    
    function test_DepositarETH_Exitoso() public {
        uint256 depositoETH = 0.1 ether;
        
        vm.prank(user1);
        banco.depositarETH{value: depositoETH}();
        
        // Verificar que se actualizó el balance
        assertEq(banco.s_balances(user1, address(0)), depositoETH); // verifica que el balance de eth del usuario es el depositoETH
        assertGt(banco.s_totalDepositadoUSD(), 0); // verifica que el total depositado en usd es mayor a 0
        assertEq(banco.s_contadorDepositos(), 1); // verifica que el contador de depositos es 1
    }
    
    function test_DepositarETH_RevertiSiEsCero() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.KipuBankV3_MontoDebeSerMayorACero.selector);
        banco.depositarETH{value: 0}();
    }
    
    function test_DepositarETH_MultipleUsuarios() public {
        uint256 depositoETH = 0.05 ether;
        
        vm.prank(user1);
        banco.depositarETH{value: depositoETH}();
        
        vm.prank(user2);
        banco.depositarETH{value: depositoETH}();
        
        assertEq(banco.s_balances(user1, address(0)), depositoETH);
        assertEq(banco.s_balances(user2, address(0)), depositoETH);
        assertEq(banco.s_contadorDepositos(), 2);
    }
    
    /*//////////////////////////////////////////////////////////////
                        TESTS DE DEPOSITOS USDC
    //////////////////////////////////////////////////////////////*/
    
    function test_DepositarUSDC_Exitoso() public {
        uint256 depositoUSDC = 600 * 10**6; // $600
        
        // Dar USDC a user1
        deal(USDC_SEPOLIA, user1, depositoUSDC);
        
        vm.startPrank(user1);
        IERC20(USDC_SEPOLIA).approve(address(banco), depositoUSDC);
        banco.depositarUSDC(depositoUSDC);
        vm.stopPrank();
        
        assertEq(banco.s_balances(user1, USDC_SEPOLIA), depositoUSDC);
        assertEq(banco.s_totalDepositadoUSD(), depositoUSDC);
        assertEq(banco.s_contadorDepositos(), 1);
    }
    
    function test_DepositarUSDC_RevertiSiExcedeBankCap() public {
        uint256 depositoExcesivo = BANK_CAP + 1;
        
        deal(USDC_SEPOLIA, user1, depositoExcesivo);
        
        vm.startPrank(user1);
        IERC20(USDC_SEPOLIA).approve(address(banco), depositoExcesivo);
        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.KipuBankV3_LimiteGlobalExcedidoUSD.selector,
                0,
                depositoExcesivo,
                BANK_CAP
            )
        );
        banco.depositarUSDC(depositoExcesivo);
        vm.stopPrank();
    }
    
    function test_DepositarUSDC_RevertiSiMontoCero() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.KipuBankV3_MontoDebeSerMayorACero.selector);
        banco.depositarUSDC(0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        TESTS DE RETIROS ETH
    //////////////////////////////////////////////////////////////*/
    
    function test_RetirarETH_Exitoso() public {
        uint256 depositoETH = 0.1 ether;
        
        // Crear un usuario con capacidad de recibir ETH
        address payable testUser = payable(address(0x123)); // Address simple
        vm.deal(testUser, 100 ether); // Darle ETH inicial
        
        // Depositar
        vm.prank(testUser);
        banco.depositarETH{value: depositoETH}();
        
        uint256 balanceAntes = testUser.balance;
        
        // Retirar la mitad
        uint256 retiroETH = 0.05 ether;
        vm.prank(testUser);
        banco.retirarETH(retiroETH);
        
        assertEq(banco.s_balances(testUser, address(0)), depositoETH - retiroETH);
        assertEq(testUser.balance, balanceAntes + retiroETH);
        assertEq(banco.s_contadorRetiros(), 1);
    }
    
    function test_RetirarETH_RevertiSiSaldoInsuficiente() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.KipuBankV3_SaldoInsuficiente.selector,
                0,
                1 ether
            )
        );
        banco.retirarETH(1 ether);
    }
    
    function test_RetirarETH_RevertiSiMontoCero() public {
        vm.prank(user1);
        vm.expectRevert(KipuBankV3.KipuBankV3_MontoDebeSerMayorACero.selector);
        banco.retirarETH(0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        TESTS DE RETIROS USDC
    //////////////////////////////////////////////////////////////*/
    
    function test_RetirarUSDC_Exitoso() public {
        uint256 depositoUSDC = 50 * 10**6;
        
        // Setup: depositar primero
        deal(USDC_SEPOLIA, user1, depositoUSDC);
        vm.startPrank(user1);
        IERC20(USDC_SEPOLIA).approve(address(banco), depositoUSDC);
        banco.depositarUSDC(depositoUSDC);
        
        // Retirar
        uint256 retiroUSDC = 25 * 10**6;
        banco.retirarUSDC(retiroUSDC);
        vm.stopPrank();
        
        assertEq(banco.s_balances(user1, USDC_SEPOLIA), depositoUSDC - retiroUSDC);
        assertEq(IERC20(USDC_SEPOLIA).balanceOf(user1), retiroUSDC);
        assertEq(banco.s_contadorRetiros(), 1);
    }
    
    function test_RetirarUSDC_RevertiSiExcedeUmbral() public {
        uint256 retiroExcesivo = UMBRAL_RETIRO + 1;
        
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.KipuBankV3_RetiroExcedeUmbral.selector,
                retiroExcesivo,
                UMBRAL_RETIRO
            )
        );
        banco.retirarUSDC(retiroExcesivo);
    }
    
    function test_RetirarUSDC_RevertiSiSaldoInsuficiente() public {
        uint256 retiroUSDC = 50 * 10**6;
        
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                KipuBankV3.KipuBankV3_SaldoInsuficiente.selector,
                0,
                retiroUSDC
            )
        );
        banco.retirarUSDC(retiroUSDC);
    }
    
    /*//////////////////////////////////////////////////////////////
                        TESTS DE FUNCIONES VIEW
    //////////////////////////////////////////////////////////////*/
    
    function test_ConsultarBalanceTotalUSD() public {
        // Depositar ETH y USDC
        uint256 depositoETH = 0.1 ether;
        uint256 depositoUSDC = 50 * 10**6;
        
        vm.prank(user1);
        banco.depositarETH{value: depositoETH}();
        
        deal(USDC_SEPOLIA, user1, depositoUSDC);
        vm.startPrank(user1);
        IERC20(USDC_SEPOLIA).approve(address(banco), depositoUSDC);
        banco.depositarUSDC(depositoUSDC);
        vm.stopPrank();
        
        uint256 balanceTotal = banco.consultarBalanceTotalUSD(user1);
        assertGt(balanceTotal, depositoUSDC); // Debe ser mayor porque incluye ETH convertido
    }
    
    function test_GetCotizacionTokenAUsdc() public view {
        uint256 amount = 0.1 ether;
        uint256 cotizacion = banco.getCotizacionTokenAUsdc(address(0), amount);
        assertGt(cotizacion, 0); // verifica que la cotizacion es mayor a 0
    }
    
    /*//////////////////////////////////////////////////////////////
                        TESTS DE LIMITES
    //////////////////////////////////////////////////////////////*/
    
    function test_BankCap_NoPermitirDepositosSiExcedeLimite() public {
        // Llenar casi al límite
        uint256 depositoCasiLimite = BANK_CAP - 1000; // Dejar margen pequeño
        
        deal(USDC_SEPOLIA, user1, BANK_CAP);
        vm.startPrank(user1);
        IERC20(USDC_SEPOLIA).approve(address(banco), BANK_CAP);
        banco.depositarUSDC(depositoCasiLimite);
        
        // Intentar depositar más del límite
        vm.expectRevert();
        banco.depositarUSDC(2000);
        vm.stopPrank();
    }
}