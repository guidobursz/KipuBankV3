// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*///////////////////////
        Imports
///////////////////////*/
//Para implementar propietario unico del contrato, pudiendo consultar quien es, poder transferir propiedad y renunciar.
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
//Para proteger de ataques de re-entrada.
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
//Interfaz para acceder a las funciones estandar de un token.
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
//Libreria para hacer mas segura la manipulacion de erc20
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title KipuBankV3
 * @author guidobursz
**/

/*  Representación del contrato Router de Uniswap V3, que permite a este contrato llamar a sus funciones externas */
interface IUniswapV2Router02 {
    // Devuelve la dirección del token WETH (Wrapped Ether), esencial para manejar swaps que involucran a ETH
    function WETH() external pure returns (address);

    /* Ejecuta un swap donde conoces la cantidad exacta de token de entrada (amountIn) y especificas la cantidad mínima a recibir (amountOutMin)*/
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);

    /* Ejecuta un swap donde la entrada es Ether nativo (usando payable) y se especifica la cantidad mínima a recibir (amountOutMin) */
    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn, 
        address[] calldata path
    ) external view returns (uint[] memory amounts);

}



contract KipuBankV3 is Ownable, ReentrancyGuard {
    
    /*///////////////////////
        Declaración de Tipos
    ///////////////////////*/
    using SafeERC20 for IERC20;

    // Dirección del Router de Uniswap V3 (ej. la dirección en Ethereum)
    IUniswapV2Router02 public immutable ROUTER;


    /*///////////////////////
        Variables Constantes
    ///////////////////////*/
    
    /// @notice declaro eth nativo
    address public constant NATIVE_TOKEN = address(0);
    
    /// Defino decimales para ambos tokens, segun normalizacion
    uint256 constant USDC_DECIMALS = 6;
    uint256 constant ETH_DECIMALS = 18;
    
    
    /*///////////////////////
        Variables Immutable
    ///////////////////////*/
    
    /// @notice Límite global del banco en USD
    uint256 public immutable i_bankCapUSD;
    /// @notice Umbral máximo de retiro por transacción en USD
    uint256 public immutable i_umbralRetiroUSD;
    

    /// @notice Dirección del token USDC
    IERC20 public immutable i_usdc;
    
    /// @notice Dirección del token WETH
    IERC20 public immutable i_weth;

    /*///////////////////////
        Variables de Estado
    ///////////////////////*/
    
    /// @notice Mapping anidado: usuario => token => balance en USD
    mapping(address user => mapping(address token => uint256 balanceUSD)) public s_balances;
    
    /// @notice Total depositado global en USD (suma de todos los tokens)
    uint256 public s_totalDepositadoUSD;
    
    /// @notice Contador global de depósitos realizados
    uint256 public s_contadorDepositos;
    
    /// @notice Contador global de retiros realizados
    uint256 public s_contadorRetiros;
    


    /*///////////////////////
            Eventos
    ///////////////////////*/
    
    /// @notice Evento emitido cuando un usuario realiza un depósito exitoso
    /// @param usuario Dirección del usuario que depositó
    /// @param token Dirección del token depositado (address(0) para ETH)
    /// @param amount Cantidad depositada en unidades del token
    /// @param amountUSD Valor del depósito en USD
    event KipuBankV3_DepositoRealizado(
        address indexed usuario, 
        address indexed token, 
        uint256 amount, 
        uint256 amountUSD
    );

    /// @notice Evento emitido cuando un usuario realiza un retiro exitoso
    /// @param usuario Dirección del usuario que retiró
    /// @param token Dirección del token retirado (address(0) para ETH)
    /// @param amount Cantidad retirada en unidades del token
    /// @param amountUSD Valor del retiro en USD (6 decimales)
    event KipuBankV3_RetiroRealizado(
        address indexed usuario, 
        address indexed token, 
        uint256 amount, 
        uint256 amountUSD
    );

    // evento que se emitirá después de cada swap exitoso
    event SwapExecuted(address indexed user, address tokenIn, address tokenOut, uint amountIn, uint amountOut);

    
    /*///////////////////////
        Errores Personalizados
    ///////////////////////*/
    
    /// @notice Error emitido cuando el monto es cero
    error KipuBankV3_MontoDebeSerMayorACero();

    /// @notice Error emitido cuando el depósito excede el límite global en USD
    /// @param totalActualUSD Total actualmente depositado en el banco
    /// @param intentoDepositoUSD Monto que se intenta depositar
    /// @param limiteUSD Límite máximo permitido (bankCap)
    error KipuBankV3_LimiteGlobalExcedidoUSD(
        uint256 totalActualUSD, 
        uint256 intentoDepositoUSD, 
        uint256 limiteUSD
    );

    /// @notice Error emitido cuando el usuario intenta retirar más de lo que tiene
    /// @param balanceDisponible Balance actual del usuario en USD
    /// @param montoSolicitado Monto que intenta retirar en USD
    error KipuBankV3_SaldoInsuficiente(uint256 balanceDisponible, uint256 montoSolicitado);

    /// @notice Error emitido cuando el retiro excede el umbral permitido por transacción
    /// @param montoSolicitadoUSD Monto que intenta retirar en USD
    /// @param umbralMaximoUSD Límite máximo por retiro en USD
    error KipuBankV3_RetiroExcedeUmbral(uint256 montoSolicitadoUSD, uint256 umbralMaximoUSD);

    /// @notice Error emitido cuando falla la transferencia de ETH
    /// @param destinatario Dirección a la que se intentó enviar
    error KipuBankV3_TransferenciaFallida(address destinatario);

    
    /*///////////////////////
        Constructor
    ///////////////////////*/
    /**
     * @param _bankCapUSD Límite máximo total de depósitos en USD (6 decimales)
     * @param _umbralRetiroUSD Monto máximo por retiro en USD (6 decimales)
     * @param _usdc Dirección del token USDC
     * @param _weth Dirección del token WETH
     * @param _owner Dirección del propietario del contrato
     * @param _router Dirección del Router de Uniswap V3
     * @dev Los valores immutable se establecen aquí y no pueden cambiar después del deployment
     */
    constructor(
            uint256 _bankCapUSD,
            uint256 _umbralRetiroUSD,
            address _usdc,
            address _weth,
            address _owner,
            address _router
        )
        Ownable(_owner)
    {
        /*
            Valores deploy:
            i_bankCapUSD = 1000000000; //1000
            _umbralRetiroUSD = 100000000; //100
            _usdc = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
            _weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
            _owner = 0x652405FdecC7fCcA771752b83D5F6DB8be46a296
            _router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        */
        i_bankCapUSD = _bankCapUSD;
        i_umbralRetiroUSD = _umbralRetiroUSD;
        i_usdc = IERC20(_usdc);
        i_weth = IERC20(_weth);
        ROUTER = IUniswapV2Router02(_router);
    }

    /*///////////////////////
        Modificadores
    ///////////////////////*/
    
    /**
    * @notice Modificador que valida que el monto sea mayor a cero
    * @dev Revierte si el valor es cero
    */
    modifier montoMayorACero(uint256 _monto) {
        if (_monto == 0) revert KipuBankV3_MontoDebeSerMayorACero();
        _;
    }


    /*///////////////////////
        Funciones Externas
    ///////////////////////*/

    /**
        * @notice Obtiene la cotización de un token a USDC
        * @param token Dirección del token a validar
        * @param amount Cantidad del token
        * @return usdcAmount Cantidad de USDC post swap
    */
    function getCotizacionTokenAUsdc(
        address token,
        uint256 amount
    ) public view returns (uint256 usdcAmount) {
        //Checks: Validar que la cantidad sea mayor a cero
        if(amount == 0) revert KipuBankV3_MontoDebeSerMayorACero();

        address[] memory path = new address[](2);
        path[0] = (token == address(0)) ? address(i_weth) : token;
        //Defino el token de salida siempre usdc
        path[1] = address(i_usdc);
        
        //Interactions: Obtener la cotización del token a USDC
        uint[] memory amounts = ROUTER.getAmountsOut(amount, path);
        //Return: Devolver la cantidad de USDC post swap
        return amounts[1];
    }

    //DEPOSITOS
    
    /**
    * @notice Permite depositar ETH nativo en la bóveda del usuario
    * @dev Convierte el ETH a USD usando el Router de Uniswap V3 y valida el límite global
    * @dev El balance se almacena en USD
    */
    function depositarETH() external payable nonReentrant {
        // Checks: Validar que se envió ETH
        if (msg.value == 0) revert KipuBankV3_MontoDebeSerMayorACero();
        
        // Checks: Obtener valor eth a  USD usando el Router de Uniswap V3
        uint256 valorUSD = getCotizacionTokenAUsdc(NATIVE_TOKEN, msg.value);
        
        // Valido limite global 
        if (s_totalDepositadoUSD + valorUSD > i_bankCapUSD) {
            revert KipuBankV3_LimiteGlobalExcedidoUSD(
                s_totalDepositadoUSD,
                valorUSD,
                i_bankCapUSD
            );
        }
        
        // Effects: Actualizar estado
        //1 actualizo el balance de eth del usuario
        s_balances[msg.sender][NATIVE_TOKEN] += msg.value;
        
        //2 actualizo el total depositado de usdc
        s_totalDepositadoUSD += valorUSD;

        //3 actualizo el contador de depositos
        s_contadorDepositos++;
        
        // Interactions: Emitir evento
        emit KipuBankV3_DepositoRealizado(
            msg.sender,
            NATIVE_TOKEN,
            msg.value,    // Monto en ETH
            valorUSD      // Monto en USD
        );
    }

    /**
    * @notice Depositar directamente USDC
    * @dev Valida el límite global
    * @dev Incrementa el balance del usuario y el total depositado
    * @dev Emite el evento KipuBankV3_DepositoRealizado
    */
    /*
    function depositarUSDC(uint256 _amount) 
        public
        nonReentrant
        montoMayorACero(_amount)
    {        
        // Validar límite global
        if (s_totalDepositadoUSD + _amount > i_bankCapUSD) {
            revert KipuBankV3_LimiteGlobalExcedidoUSD(
                s_totalDepositadoUSD,
                _amount,
                i_bankCapUSD
            );
        }
        
        // Effects: Actualizar estado
        s_balances[msg.sender][address(i_usdc)] += _amount;
        s_totalDepositadoUSD += _amount;
        s_contadorDepositos++;
        
        //Interactions: Transferir tokens y emitir evento
        emit KipuBankV3_DepositoRealizado(
            msg.sender,
            address(i_usdc),
            _amount,
            _amount
        );
        
        IERC20(address(i_usdc)).safeTransferFrom(msg.sender, address(this), _amount);
    }
    */
    function depositarUSDC(uint256 _amount) external nonReentrant montoMayorACero(_amount) {
        _depositarUSDCInternal(_amount);
    }

    /**
    * @notice Depositar cualquier token soportado
    * @dev Valida el límite global
    * @dev Incrementa el balance del usuario y el total depositado
    * @dev Emite el evento KipuBankV3_DepositoRealizado
    * @param _token Dirección del token a depositar
    * @param _amount Cantidad del token a depositar
    */
    function depositarToken(address _token, uint256 _amount) 
        external
        nonReentrant
        montoMayorACero(_amount)
    {

        if(_token == address(i_usdc)) {
            _depositarUSDCInternal(_amount);
            return;
        }

        // Checks: Obtener el valor en USDC del token ingresado
        uint256 valorUSD = getCotizacionTokenAUsdc(_token, _amount);

        // Checks: Validar límite global
        if (s_totalDepositadoUSD + valorUSD > i_bankCapUSD) {
            revert KipuBankV3_LimiteGlobalExcedidoUSD(
                s_totalDepositadoUSD,
                valorUSD,
                i_bankCapUSD
            );
        }

        //Interactions: Recibir tokens del usuario
        //1. Recibir tokens del usuario
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        
        // Interactions: Aprobar el router para gastar los tokens
        IERC20(_token).safeApprove(address(ROUTER), _amount);
        
        // Interactions: Ejecutar swap TOKEN → USDC
        address[] memory path = new address[](2);
        path[0] = _token;
        path[1] = address(i_usdc);
        
        uint256 minAmountOut = (valorUSD * 995) / 1000; // 0.5% slippage

        uint[] memory amounts = ROUTER.swapExactTokensForTokens(
            _amount,
            minAmountOut,
            path,
            address(this),
            block.timestamp + 300
        );
        
        uint256 usdcRecibido = amounts[1];

        // Effects: Actualizar estado
        s_balances[msg.sender][address(i_usdc)] += usdcRecibido;
        s_totalDepositadoUSD += usdcRecibido;
        s_contadorDepositos++;


        emit SwapExecuted(msg.sender, _token, address(i_usdc), _amount, usdcRecibido);
        emit KipuBankV3_DepositoRealizado(
            msg.sender,
            _token,
            _amount,
            usdcRecibido
        );

    }


    //Funcion interna de depositarUsdc en caso de tener que llamar desde depositarToken y evitar conflicto de reentrancy
    /**
    * @dev Lógica interna para depositar USDC (sin modificadores)
    */
    function _depositarUSDCInternal(uint256 _amount) internal {
        // Validar límite global
        if (s_totalDepositadoUSD + _amount > i_bankCapUSD) {
            revert KipuBankV3_LimiteGlobalExcedidoUSD(
                s_totalDepositadoUSD,
                _amount,
                i_bankCapUSD
            );
        }
        
        // Effects: Actualizar estado
        s_balances[msg.sender][address(i_usdc)] += _amount;
        s_totalDepositadoUSD += _amount;
        s_contadorDepositos++;
        
        // Interactions
        emit KipuBankV3_DepositoRealizado(
            msg.sender,
            address(i_usdc),
            _amount,
            _amount
        );
        
        i_usdc.safeTransferFrom(msg.sender, address(this), _amount);
    }








    //RETIROS


    /**
    * @notice Permite retirar ETH nativo de la bóveda del usuario
    * @param _amountETH Cantidad de ETH a retirar en wei
    * @dev Valida saldo suficiente y umbral de retiro en USD
    */
    function retirarETH(uint256 _amountETH) 
        external 
        nonReentrant 
        montoMayorACero(_amountETH) 
    {
        // Checks: Validar saldo suficiente de ETH
        if (s_balances[msg.sender][NATIVE_TOKEN] < _amountETH) {
            revert KipuBankV3_SaldoInsuficiente(
                s_balances[msg.sender][NATIVE_TOKEN],
                _amountETH
            );
        }
        
        // Checks: Convertir ETH a USD para validar umbral
        uint256 valorUSD = getCotizacionTokenAUsdc(NATIVE_TOKEN, _amountETH);
        
        // Checks: Validar umbral de retiro
        if (valorUSD > i_umbralRetiroUSD) {
            revert KipuBankV3_RetiroExcedeUmbral(valorUSD, i_umbralRetiroUSD);
        }
        
        // Effects: Actualizar estado
        s_balances[msg.sender][NATIVE_TOKEN] -= _amountETH;  // resto eth
        s_totalDepositadoUSD -= valorUSD;                    // resto valor usdc
        s_contadorRetiros++;
        
        // Interactions: Emitir evento y transferir ETH
        emit KipuBankV3_RetiroRealizado(
            msg.sender,
            NATIVE_TOKEN,
            _amountETH,
            valorUSD
        );
        
        _transferirEth(msg.sender, _amountETH);
    }



    /**
    * @notice Permite retirar USDC de la bóveda del usuario
    * @param _amount Cantidad de USDC a retirar
    * @dev Valida saldo suficiente y umbral de retiro en USD
    */
    function retirarUSDC(uint256 _amount) 
        external 
        nonReentrant 
        montoMayorACero(_amount)
    {
        // Checks: Validar umbral de retiro
        if (_amount > i_umbralRetiroUSD) {
            revert KipuBankV3_RetiroExcedeUmbral(_amount, i_umbralRetiroUSD);
        }

        // Checks: Validar saldo suficiente
        if (s_balances[msg.sender][address(i_usdc)] < _amount) {
            revert KipuBankV3_SaldoInsuficiente(
                s_balances[msg.sender][address(i_usdc)],
                _amount
            );
        }
        
        // Effects: Actualizar estado
        s_balances[msg.sender][address(i_usdc)] -= _amount;
        //2 actualizo el total depositado de usdc
        s_totalDepositadoUSD -= _amount;
        //3 actualizo el contador de retiros
        s_contadorRetiros++;
        
        // Interactions: Emitir evento y transferir USDC
        emit KipuBankV3_RetiroRealizado(
            msg.sender,
            address(i_usdc),
            _amount,
            _amount
        );

        i_usdc.safeTransfer(msg.sender, _amount);
    }

    
    /*///////////////////////
        Funciones Privadas
    ///////////////////////*/
        
    /**
    * @notice Función privada para transferir ETH de forma segura
    * @param _destinatario Dirección que recibirá el ETH
    * @param _monto Cantidad de ETH a transferir en wei
    * @dev Usa call para enviar ETH y revierte si la transferencia falla
    * @dev Esta función es privada y solo puede ser llamada internamente
    */
    function _transferirEth(address _destinatario, uint256 _monto) private {
        (bool success, ) = _destinatario.call{value: _monto}("");
        if (!success) revert KipuBankV3_TransferenciaFallida(_destinatario);
    }
    
    /*///////////////////////
        Funciones View/Pure
    ///////////////////////*/
    /**
    * @notice Consulta el balance total de un usuario en USD (todos los tokens)
    * @param _usuario Dirección del usuario a consultar
    * @return balanceTotalUSD_ Balance total en USD (6 decimales)
    */
    function consultarBalanceTotalUSD(address _usuario) 
        external 
        view 
        returns (uint256 balanceTotalUSD_) 
    {
        // Obtener balance de ETH y convertir a USDC
        uint256 ethBalance = s_balances[_usuario][NATIVE_TOKEN];
        uint256 ethEnUSDC = 0;
        
        if (ethBalance > 0) {
            ethEnUSDC = getCotizacionTokenAUsdc(NATIVE_TOKEN, ethBalance);
        }
        
        // Sumar ETH convertido + USDC directo
        balanceTotalUSD_ = ethEnUSDC + s_balances[_usuario][address(i_usdc)];
    }

    //Funcion para ver le umbralMaximo de retiro
    function getUmbralRetiro() external view returns (uint256) {
        return i_umbralRetiroUSD;
    }


}