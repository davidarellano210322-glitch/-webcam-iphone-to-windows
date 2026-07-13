# Arquitectura Nativa USB: iOS (iPhone) a Windows

Para llevar este prototipo a una aplicación comercial/profesional con **latencia cero (menos de 15 milisegundos)** y resolución de hasta 1080p a 60 FPS por cable USB, debemos cambiar el navegador web por código nativo y compresión dedicada por hardware.

A continuación, se detalla la arquitectura de rendimiento extremo.

---

## 1. La Fórmula del Rendimiento Extremo (Latencia < 15ms)

El lag del prototipo actual se debe a la compresión JPEG en JavaScript (CPU) y la transmisión por WiFi. Para eliminarlo, utilizaremos esta cadena de procesamiento:

```
[ Cámara iPhone ] ──(Raw YUV)──> [ Hardware Encoder (H.264) ] ──(Video Stream)──> [ Conexión USB (usbmuxd) ]
                                                                                         │
[ Cámara DirectShow (OBS/Zoom) ] <──(YUV/RGBA)── [ Shared Memory (MMF) ] <──(Decodificado)── [ PC C# / GPU ]
```

---

## 2. El Cliente iOS: Captura y Codificación por Hardware

En lugar del navegador web, utilizaremos una aplicación nativa (en **Swift** directamente o a través de **Flutter** utilizando enlaces nativos *Platform Channels*):

* **Captura a 60 FPS:** Usamos la API `AVFoundation` de iOS para capturar los fotogramas en bruto en formato `YUV420` o `NV12` directamente del sensor de la cámara.
* **Codificación por GPU (VideoToolbox):** 
  * En lugar de comprimir fotos JPEG individuales, enviamos los fotogramas al framework nativo de Apple `VideoToolbox`.
  * Este framework comprime el video en **H.264 / H.265 (HEVC)** usando los chips dedicados de la GPU del iPhone.
  * **Configuración de latencia ultra-baja:** Se configura el codificador con el perfil `kVTCompressionPropertyKey_RealTime` y desactivamos los *B-Frames* (fotogramas bidireccionales que requieren almacenamiento en buffer). El retraso de codificación es de **menos de 2 milisegundos**.
* **Socket de Salida:** Los paquetes codificados (NAL Units) se envían a un socket TCP local corriendo en el puerto `6000` dentro del iPhone.

---

## 3. La Conexión USB Física (usbmuxd)

En iOS, no se puede abrir una conexión USB libremente como en Android con ADB. Apple utiliza el protocolo **usbmuxd** (USB Multiplexor Daemon), que se instala automáticamente en Windows junto con iTunes.

* **Cómo funciona:** `usbmuxd` escucha en la PC conexiones USB de dispositivos Apple y expone un socket del sistema.
* **Túnel de Puertos (iproxy):**
  * La aplicación de Windows C# se conecta a `usbmuxd` usando librerías de C# como `iMobileDevice-net`.
  * Se abre un túnel físico: el puerto `6000` de tu iPhone se mapea al puerto `6000` de tu `localhost` en Windows a través del cable Lightning o USB-C.
  * **Velocidad:** La transferencia física por cable USB-C (en iPhone 15 Pro/16) es de hasta 10 Gbps; en cables Lightning (USB 2.0) es de 480 Mbps. El tiempo de tránsito de red es de **0.5 milisegundos**.

---

## 4. El Receptor en Windows (C# .NET)

La aplicación de Windows recibe el flujo de video H.264 codificado a través del túnel USB local (`127.0.0.1:6000`):

* **Decodificación por Hardware (GPU):**
  * Para evitar consumir la CPU de la computadora, el programa en C# decodifica el flujo H.264 utilizando la GPU del PC a través de **Windows Media Foundation (MFT)** o **FFmpeg con DXVA2/D3D11VA**.
  * El video se decodifica directamente a texturas en memoria de video (DirectX/OpenGL) o a memoria RAM en formato `NV12` o `RGBA`.
* **Memoria Compartida de Alta Velocidad (IPC):**
  * El frame decodificado se escribe en un archivo mapeado en memoria RAM (`MemoryMappedFile`) que comparte con la DLL de la cámara virtual (el DirectShow Filter).
  * Se dispara un evento nativo de Windows (`EventWaitHandle`) para notificar a la cámara virtual que hay un nuevo fotograma disponible.

---

## 5. Tabla Comparativa de Rendimiento

| Característica | Prototipo WiFi (Actual) | Solución Nativa USB (Final) |
| :--- | :--- | :--- |
| **Medio físico** | Aire (Ondas de Radio WiFi) | Cable de cobre/fibra (USB 3.0 / Lightning) |
| **Algoritmo de compresión** | Motion JPEG (Fotos consecutivas) | H.264 / H.265 (Hardware Stream de Video) |
| **Consumo de CPU en celular** | Alto (Compresión JPEG en JavaScript) | Casi 0% (Procesador de video dedicado en chip Apple) |
| **Ancho de banda necesario** | ~15 Mbps (Ineficiente, sensible a interferencias) | ~3 Mbps (Muy eficiente y constante) |
| **Latencia Total** | ~100ms - 300ms (Depende del router) | **~10ms - 15ms (Instantáneo)** |

---

## 6. Siguientes Pasos para Desarrollar la App Nativa

Si quieres avanzar hacia la aplicación nativa, el orden de desarrollo recomendado es:

1. **Instalación de Herramientas de Compilación nativas:**
   * Instalar **Visual Studio 2022** con soporte para desarrollo de escritorio de .NET (C#).
   * Instalar **Flutter SDK** en tu máquina de desarrollo.
2. **Crear el Cliente Swift/iOS:**
   * Desarrollar la lógica de captura con `AVCaptureSession`, enviar los búferes de imagen a `VTCompressionSession` (VideoToolbox) y transmitir por socket.
3. **Crear el Servidor en C# con usbmuxd:**
   * Implementar la detección de dispositivos iOS en C# mediante `usbmuxd` para levantar el túnel USB automáticamente al enchufar el teléfono.
4. **Implementar el Pipeline DirectShow:**
   * Conectar la salida del decodificador H.264 de C# a la DLL de cámara virtual.
