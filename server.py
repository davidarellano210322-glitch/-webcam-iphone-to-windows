from aiohttp import web
import socket
import cv2
import numpy as np
import pyvirtualcam
import os
import sys
import ssl

routes = web.RouteTableDef()
cam = None

@routes.get('/')
async def handle_index(request):
    try:
        template_path = os.path.join(os.path.dirname(__file__), 'templates', 'index.html')
        with open(template_path, 'r', encoding='utf-8') as f:
            html = f.read()
        return web.Response(text=html, content_type='text/html')
    except Exception as e:
        return web.Response(text=f"Error leyendo index.html: {e}", status=500)

@routes.get('/ws')
async def handle_ws(request):
    global cam
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    print("\n[+] Celular conectado a la transmisión de video.")

    async for msg in ws:
        if msg.type == web.WSMsgType.BINARY:
            try:
                # Decodificar la imagen JPEG recibida en binario
                data = msg.data
                nparr = np.frombuffer(data, np.uint8)
                img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                if img is None:
                    continue

                # Convertir de BGR (formato de OpenCV) a RGB (esperado por pyvirtualcam)
                img_rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
                h, w, c = img_rgb.shape

                # Inicializar o reiniciar la cámara virtual si la resolución cambia
                if cam is None or cam.width != w or cam.height != h:
                    if cam is not None:
                        cam.close()
                    try:
                        cam = pyvirtualcam.Camera(width=w, height=h, fps=30, backend='unitycapture')
                        print(f"[+] Cámara virtual activada: {w}x{h} en dispositivo '{cam.device}'")
                    except Exception as ex:
                        print(f"[-] ERROR al iniciar cámara virtual: {ex}")
                        print("    Asegúrate de haber instalado el driver UnityCapture ejecutando driver/Install/Install.bat como Administrador.")
                        cam = None

                if cam is not None:
                    # Enviar el frame a la cámara virtual de Windows
                    cam.send(img_rgb)
                    sys.stdout.write(f"\rStreaming a la webcam virtual: {w}x{h} px | Recibiendo bytes... ")
                    sys.stdout.flush()

            except Exception as e:
                print(f"\n[-] Error procesando frame: {e}")
        elif msg.type == web.WSMsgType.ERROR:
            print(f"\n[-] Conexión cerrada con error: {ws.exception()}")

    print("\n[-] Celular desconectado.")
    return ws

def get_local_ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(('10.255.255.255', 1))
        IP = s.getsockname()[0]
    except Exception:
        IP = '127.0.0.1'
    finally:
        s.close()
    return IP

def setup_ssl(ip):
    cert_file = "cert.pem"
    key_file = "key.pem"
    
    if not os.path.exists(cert_file) or not os.path.exists(key_file):
        print("[*] No se encontraron certificados SSL en el directorio. Generando certificados auto-firmados...")
        try:
            import cryptography
        except ImportError:
            print("[*] Instalando 'cryptography' para autogenerar certificado SSL...")
            import subprocess
            subprocess.run([sys.executable, "-m", "pip", "install", "cryptography"], check=True)
            
        import datetime
        import ipaddress
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization

        # Generar llave privada
        key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )

        # Definir emisor y sujeto
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, u"CL"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, u"Santiago"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, u"Antigravity Webcam"),
            x509.NameAttribute(NameOID.COMMON_NAME, ip),
        ])

        # Construir certificado
        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.datetime.now(datetime.timezone.utc)
        ).not_valid_after(
            datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=365)
        ).add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName(u"localhost"),
                x509.IPAddress(ipaddress.ip_address(ip))
            ]),
            critical=False,
        ).sign(key, hashes.SHA256())

        # Guardar en disco
        with open(key_file, "wb") as f:
            f.write(key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption(),
            ))

        with open(cert_file, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))
            
        print("[+] Certificados SSL generados correctamente.")

    # Crear contexto SSL
    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(cert_file, key_file)
    return ssl_context

if __name__ == '__main__':
    ip = get_local_ip()
    port = 8000
    
    # Configurar y obtener contexto SSL (Requerido para iOS)
    ssl_context = setup_ssl(ip)
    
    print("=" * 65)
    print("            ANTIGRAVITY WEBCAM SERVER - HTTPS ACTIVADO")
    print("=" * 65)
    print("  Instrucciones para iPhone y iOS (WiFi seguro):")
    print("  1. Asegúrate de que tu iPhone esté en el mismo WiFi que la PC.")
    print("  2. Abre este enlace en el navegador Safari de tu iPhone:")
    print(f"\n     -> https://{ip}:{port}\n")
    print("  3. ALERTA DE SEGURIDAD EN IPHONE:")
    print("     Verás un aviso de 'Sitio no seguro' (es normal por ser certificado local).")
    print("     Toca en 'Mostrar Detalles' o 'Opciones Avanzadas'")
    print("     y selecciona 'Visitar este sitio' / 'Proceder'.")
    print("  4. Concede permisos de cámara al navegador y transmite.")
    print("=" * 65)
    print("[*] Iniciando servidor HTTPS...")

    app = web.Application()
    app.add_routes(routes)
    web.run_app(app, host='0.0.0.0', port=port, ssl_context=ssl_context, print=None)
