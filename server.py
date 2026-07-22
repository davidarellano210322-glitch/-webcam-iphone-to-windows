from aiohttp import web
import socket
import cv2
import numpy as np
import pyvirtualcam
import os
import sys
import ssl
import asyncio
import struct

routes = web.RouteTableDef()
cam = None

# Variable global para almacenar la IP local
LOCAL_IP = '127.0.0.1'

@routes.get('/')
async def handle_index(request):
    try:
        template_path = os.path.join(os.path.dirname(__file__), 'templates', 'index.html')
        with open(template_path, 'r', encoding='utf-8') as f:
            html = f.read()
        return web.Response(text=html, content_type='text/html')
    except Exception as e:
        return web.Response(text=f"Error leyendo index.html: {e}", status=500)

@routes.get('/info')
async def handle_info(request):
    """Endpoint que devuelve la info del servidor para la app Flutter"""
    return web.json_response({
        'server': 'NeoCamo Studio',
        'version': '2.5.0',
        'ip': LOCAL_IP,
        'port': 8000,
        'status': 'ready'
    })

@routes.get('/ws')
async def handle_ws(request):
    global cam
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    print("\n[+] Celular conectado a la transmision de video.")

    async for msg in ws:
        if msg.type == web.WSMsgType.BINARY:
            try:
                # Decodificar la imagen recibida en binario
                data = msg.data
                nparr = np.frombuffer(data, np.uint8)
                
                # Intentar decodificar como JPEG primero
                img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                if img is None:
                    # Si no es JPEG, intentar como BGRA crudo
                    # Calcular dimensiones asumiendo aspecto 16:9
                    total_pixels = len(data) // 4
                    if total_pixels > 0:
                        h = int((total_pixels * 9 / 16) ** 0.5)
                        w = total_pixels // h if h > 0 else 0
                        if w > 0 and h > 0:
                            img = np.frombuffer(data, np.uint8).reshape((h, w, 4))
                            img = cv2.cvtColor(img, cv2.COLOR_BGRA2BGR)
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
                    sys.stdout.write(f"\rStreaming a webcam virtual: {w}x{h} px | {len(data)} bytes/frame   ")
                    sys.stdout.flush()

            except Exception as e:
                print(f"\n[-] Error procesando frame: {e}")
        elif msg.type == web.WSMsgType.ERROR:
            print(f"\n[-] Conexion cerrada con error: {ws.exception()}")

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

async def udp_broadcast_server():
    """Escucha broadcasts UDP para auto-descubrimiento desde la app Flutter"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setblocking(False)
    
    # Bind al puerto 8888 para auto-descubrimiento
    try:
        sock.bind(('0.0.0.0', 8888))
        print("[*] Auto-descubrimiento UDP escuchando en puerto 8888")
    except Exception as e:
        print(f"[-] No se pudo iniciar auto-descubrimiento UDP: {e}")
        return

    loop = asyncio.get_event_loop()
    
    while True:
        try:
            data, addr = await loop.sock_recvfrom(sock, 1024)
            message = data.decode('utf-8', errors='ignore').strip()
            print(f"[UDP] Broadcast recibido de {addr}: {message}")
            
            if message == 'NEOCAMO_DISCOVER':
                # Responder con la IP y puerto del servidor
                response = f"NEOCAMO_SERVER:{LOCAL_IP}:8000"
                await loop.sock_sendto(sock, response.encode('utf-8'), addr)
                print(f"[UDP] Respondiendo a {addr}: {response}")
        except Exception:
            await asyncio.sleep(0.1)

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

        key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )

        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, u"CL"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, u"Santiago"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, u"Antigravity Webcam"),
            x509.NameAttribute(NameOID.COMMON_NAME, ip),
        ])

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

        with open(key_file, "wb") as f:
            f.write(key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption(),
            ))

        with open(cert_file, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))
            
        print("[+] Certificados SSL generados correctamente.")

    ssl_context = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
    ssl_context.load_cert_chain(cert_file, key_file)
    return ssl_context

async def main_async():
    """Inicia servidor HTTPS + servidor UDP de auto-descubrimiento"""
    global LOCAL_IP
    LOCAL_IP = get_local_ip()
    port = 8000
    
    ssl_context = setup_ssl(LOCAL_IP)
    
    print("=" * 65)
    print("         NEOCAMO STUDIO SERVER - HTTPS + AUTO-DISCOVERY")
    print("=" * 65)
    print(f"  IP local detectada: {LOCAL_IP}")
    print(f"  Puerto HTTPS: {port}")
    print(f"  Auto-descubrimiento UDP: puerto 8888")
    print("=" * 65)
    print("  La app Flutter detectara este servidor automaticamente.")
    print("  No necesitas introducir la IP manualmente!")
    print("=" * 65)
    print("[*] Iniciando servidor HTTPS + UDP broadcast...")
    
    app = web.Application()
    app.add_routes(routes)
    
    # Iniciar servidor HTTP/HTTPS
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, host='0.0.0.0', port=port, ssl_context=ssl_context)
    await site.start()
    
    print(f"[+] Servidor HTTPS escuchando en https://{LOCAL_IP}:{port}")
    
    # Iniciar servidor UDP de auto-descubrimiento en paralelo
    asyncio.create_task(udp_broadcast_server())
    print("[+] Auto-descubrimiento UDP activo en puerto 8888")
    print("=" * 65)
    
    # Mantener el servidor corriendo
    while True:
        await asyncio.sleep(3600)

if __name__ == '__main__':
    try:
        asyncio.run(main_async())
    except KeyboardInterrupt:
        print("\n[*] Servidor detenido por el usuario.")
