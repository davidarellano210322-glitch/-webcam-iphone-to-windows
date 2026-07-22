# 📱 NeoCamo Monitor - Guía de Instalación en iPhone

## ¿Qué es este archivo?

Este IPA fue compilado **sin firma de código** (`--no-codesign`), lo que significa que Apple no permite instalarlo directamente tocándolo. Necesitas "firmarlo" localmente con tu propio Apple ID antes de instalarlo en tu iPhone.

Esto es completamente normal para apps de código abierto que no están en la App Store.

---

## 🚀 Instalación Rápida (Recomendado: AltStore)

### Requisitos
- Windows 10/11 o macOS
- iTunes instalado (para que Windows reconozca el iPhone)
- Cable USB
- Tu Apple ID (no necesitas cuenta de desarrollador paga)

### Pasos

1. **Descarga el IPA**
   - Ve a la pestaña "Actions" del repositorio en GitHub
   - Selecciona el último workflow exitoso
   - Descarga el artefacto "NeoCamo-iOS-IPA"
   - Descomprime el archivo .zip para obtener `Runner.ipa`

2. **Instala AltServer en tu PC**
   - Descarga AltServer desde: https://altstore.io
   - Instálalo siguiendo las instrucciones del sitio

3. **Conecta tu iPhone**
   - Conecta tu iPhone por USB a la PC
   - Si te pregunta "Confiar en esta computadora", presiona **Sí**
   - Asegúrate de que iTunes reconozca el dispositivo

4. **Instala AltStore en tu iPhone**
   - Abre AltServer en tu PC (icono en la bandeja del sistema)
   - Click en "Install AltStore" → selecciona tu iPhone
   - Ingresa tu Apple ID cuando se te pida
   - Espera a que se instale AltStore en tu iPhone

5. **Instala NeoCamo con AltStore**
   - Abre AltStore en tu iPhone
   - Ve a la pestaña "My Apps"
   - Toca el botón "+" en la esquina superior izquierda
   - Selecciona el archivo `Runner.ipa` que descargaste
   - AltStore lo firmará e instalará automáticamente

6. **¡Listo!** NeoCamo aparecerá en tu pantalla de inicio

---

## 🔧 Instalación Alternativa: Sideloadly

Si AltStore no te funciona, usa Sideloadly:

1. Descarga Sideloadly desde: https://sideloadly.io
2. Instálalo y ábrelo
3. Conecta tu iPhone por USB
4. Arrastra `Runner.ipa` a la ventana de Sideloadly
5. Ingresa tu Apple ID
6. Click en "Start"
7. Sideloadly firmará e instalará la app

---

## ⚠️ Importante: Renovación cada 7 días

Las apps instaladas con Apple ID gratuito (sin cuenta de desarrollador paga) **expiran cada 7 días**. Después de eso necesitas:

- **AltStore:** Abre AltStore en tu iPhone mientras esté en la misma red WiFi que tu PC con AltServer, y AltStore renovará la app automáticamente
- **Sideloadly:** Repite el proceso de instalación

### ¿Quieres evitar la renovación?
Compra una cuenta de **Apple Developer Program** ($99 USD/año):
1. Conéctate a Xcode → Settings → Accounts → Agrega tu Apple ID
2. O usa Sideloadly con tu cuenta de desarrollador
3. La app durará 1 año sin renovar

---

## 🎯 Después de instalar

1. Abre NeoCamo en tu iPhone
2. La primera vez te pedirá permisos de **Cámara**, **Micrófono** y **Red Local**
3. Acepta todos los permisos
4. En tu PC, abre NeoCamo Studio (la app de Windows)
5. Conecta tu iPhone por USB o asegúrate de estar en el mismo WiFi
6. Toca "Conectar por WiFi" o "Modo Prioridad USB"
7. ¡La vista previa de cámara aparecerá en el monitor!

---

## 🐛 Solución de problemas

### "No se puede verificar el desarrollador"
- Ve a Ajustes → General → VPN y gestión de dispositivos
- Toca tu Apple ID → "Confiar"

### La app se cierra al abrirla
- Asegúrate de que el IPA no haya expirado (>7 días)
- Reinstala con AltStore/Sideloadly

### No se ve la cámara en la PC
- Verifica que el driver Unity Capture esté instalado en Windows
- Ejecuta `driver/Install/Install.bat` como Administrador
- Verifica que NeoCamo Studio esté abierto en la PC

### No conecta por USB
- Abre iTunes y asegúrate de que reconozca el iPhone
- Presiona "Confiar en esta computadora" en el iPhone
- Reinicia el servicio Apple Mobile Device Service en Windows

---

## 📦 Build info

- **Versión:** 2.5.0
- **Build:** Automático via GitHub Actions
- **Canal:** Debug (sin optimizaciones de release)
- **Firma:** Sin firmar (requiere sideloading)
