# 🏦 KipuBankV3 - Banco DeFi Multi-Token con Integración Uniswap V2

**Contrato deployado en Sepolia:** [`0xD11c4bA48f67915a5Bf1f6a31721a1c9C5A7fBdC`](https://sepolia.etherscan.io/address/0xd11c4ba48f67915a5bf1f6a31721a1c9c5a7fbdc)

**Autor:** guidobursz  
**Versión:** 3.0  
**Solidity:** 0.8.26  
**Network:** Ethereum Sepolia Testnet

---


## 🎯 **Descripción General**

KipuBankV3 es un banco DeFi descentralizado que permite a los usuarios depositar múltiples tipos de tokens (ETH nativo, USDC, y cualquier ERC20 soportado por Uniswap V2) y los gestiona automáticamente convirtiéndolos a USDC para mantener una contabilidad unificada en dólares.

- Depositas **ETH** → Se guarda como ETH
- Depositas **USDC** → Se guarda como USDC
- Depositas **cualquier otro token** (WETH, DAI, etc.) → Se convierte automáticamente a USDC vía Uniswap

Todo tu balance se calcula y muestra en dólares (USDC), sin importar qué tokens depositaste.

---

## ✨ **Características Principales**

### **1. Depósitos Multi-Token**

### **2. Sistema de Retiros**

### **3. Consultas y Gestión**

### **4. Límites de Seguridad**
- **Bank Cap:** Límite global de $1,000 USD en depósitos totales
- **Umbral de Retiro:** Máximo $100 USD por transacción de retiro


### **5. Seguridad Robusta**
- ✅ ReentrancyGuard en todas las funciones externas
- ✅ SafeERC20 para transferencias seguras de tokens
- ✅ Patrón CEI (Checks-Effects-Interactions)
- ✅ Ownable para funciones administrativas
- ✅ Errores personalizados con información detallada

---

### **Componentes Principales**
```
KipuBankV3
├── Herencia
│   ├── Ownable (OpenZeppelin)
│   └── ReentrancyGuard (OpenZeppelin)
├── Interfaces
│   └── IUniswapV2Router02 (Integración DEX)
├── Tokens Soportados
│   ├── ETH (Nativo)
│   ├── USDC (ERC20)
│   └── Cualquier ERC20 con par USDC en Uniswap
└── Librerías
    └── SafeERC20 (Transferencias seguras)
```

### **Contabilidad Unificada**

Todos los balances se almacenan en USD (6 decimales USDC):

---

## **Deploy**

### **Requisitos Previos**
```bash
# 1. Instalar Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# 2. Clonar repositorio
git clone https://github.com/guidobursz/KipuBankV3
cd KipuBankV3

# 3. Instalar dependencias
forge install
```

### **Configuración**

Crear archivo `.env`:
```bash
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/TU_API_KEY
PRIVATE_KEY=tu_private_key_aqui
ETHERSCAN_API_KEY=tu_etherscan_api_key
OWNER_ADDRESS=tu_address_de_owner
```

### **Compilar**
```bash
forge build
```

### **Deployar en Sepolia**
```bash
# Cargar variables de entorno
source .env

# Deploy con verificación automática en red sepolia
forge script script/DeployKipuBankV3.s.sol:DeployKipuBankV3 \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  -vvvv
```


---

## 🧠 **Decisiones de Diseño**

### **1. ¿Por qué Uniswap V2 y no V3?**

**Decisión:** Integración con Uniswap V2 Router

**Razones:**
- ✅ **Simplicidad:** V2 tiene una interfaz más directa para swaps básicos
- ✅ **Estabilidad:** Protocolo maduro y ampliamente testeado
- ✅ **Compatibilidad:** Mejor soporte en testnets
- ⚠️ **Trade-off:** V3 ofrece mejor eficiencia de capital, pero mayor complejidad

### **2. Conversión Automática a USDC**

**Decisión:** Todo token ERC20 se convierte automáticamente a USDC

**Razones:**
- ✅ **UX mejorada:** Usuario no necesita hacer swaps manualmente
- ✅ **Contabilidad simplificada:** Un solo token base para cálculos
- ✅ **Menor superficie de ataque:** Menos variedad de tokens almacenados
- ⚠️ **Trade-off:** Usuario pierde exposición a precio del token original

### **3. ETH se guarda como ETH (no se convierte)**

**Decisión:** ETH nativo no se swapea, se almacena directamente

**Razones:**
- ✅ **Gas efficiency:** Evita costos de swap innecesarios
- ✅ **Flexibilidad:** ETH es el activo más líquido
- ✅ **Preferencia del usuario:** Muchos prefieren holdear ETH
- ⚠️ **Trade-off:** Balance mixto (ETH + USDC) en lugar de 100% USDC


### **5. Límites Immutable**

**Decisión:** Bank Cap y Umbral de Retiro son immutable

**Razones:**
- ✅ **Transparencia:** Usuarios conocen límites desde deployment
- ✅ **Confianza:** Owner no puede cambiar reglas después
- ⚠️ **Trade-off:** No se puede ajustar sin redeployar contrato

### **6. No se permiten retiros de tokens arbitrarios**

**Decisión:** Solo se puede retirar ETH o USDC, no tokens intermedios

**Razones:**
- ✅ **Seguridad:** Evita manipulación de balances
- ✅ **Coherencia:** El contrato swapea automáticamente, el retiro debe ser consistente
- ⚠️ **Trade-off:** Menor flexibilidad para el usuario

---


## 🧪 **Testing**

### **Ejecutar Tests**
```bash
# Todos los tests
forge test

# Con detalles
forge test -vvv

# Con gas report
forge test --gas-report

# Cobertura
forge coverage
```

### **Cobertura de Tests Actual**
```bash
forge coverage --report summary
```

**Resultado esperado:** ≥ 50% de cobertura de código

### **Casos de Prueba Implementados**

- ✅ Deployment y configuración inicial
- ✅ Depósito de ETH (exitoso, reverting con amount = 0)
- ✅ Depósito de USDC (exitoso, exceder bank cap, amount = 0)
- ✅ Depósito de tokens ERC20 con swap automático
- ✅ Retiro de ETH (exitoso, saldo insuficiente, amount = 0)
- ✅ Retiro de USDC (exitoso, exceder umbral, saldo insuficiente)
- ✅ Consultas view (balance total, cotizaciones)
- ✅ Validación de límites (bank cap, umbral retiro)
- ✅ Ownership y control de acceso

### **Metodología de Testing**

**Approach:** Testing basado en fork de Sepolia para mayor realismo

**Ventajas:**
- Interacción real con Uniswap deployado
- Precios y liquidez reales (aunque limitados en testnet)
- Valida integraciones externas

**Herramientas:**
- **Foundry:** Framework principal de testing
- **Forge:** Test runner
- **Anvil:** Local testnet para desarrollo rápido
- **Cast:** Interacción con contratos desde CLI

---

## ⚠️ **Limitaciones Conocidas**

### **1. Liquidez en Sepolia**

**Problema:** Los pools de Uniswap V2 en Sepolia tienen liquidez muy baja o inexistente.

**Impacto:**
- Swaps pueden tener slippage >90%
- Precios muy distorsionados vs mainnet
- Depósitos de tokens pueden fallar completamente

**Ejemplo real:**
```
Depósito: 0.0167 WETH (~$247 USD en mainnet)
Recibido: 2.734 USDC
Pérdida: ~98.9%
```
