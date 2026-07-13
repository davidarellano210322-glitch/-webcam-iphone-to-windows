import os
import sys
import urllib.request
import zipfile
import subprocess
import shutil

ADB_ZIP_URL = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
BIN_DIR = os.path.join(os.path.dirname(__file__), "bin")
ADB_EXE = os.path.join(BIN_DIR, "platform-tools", "adb.exe")

def download_progress(block_num, block_size, total_size):
    read_so_far = block_num * block_size
    if total_size > 0:
        percent = min(100, (read_so_far * 100) / total_size)
        sys.stdout.write(f"\rDescargando ADB: {percent:.1f}% ({read_so_far // 1024} KB / {total_size // 1024} KB)")
    else:
        sys.stdout.write(f"\rDescargando ADB: {read_so_far // 1024} KB")
    sys.stdout.flush()

def setup_adb():
    if os.path.exists(ADB_EXE):
        print("[+] ADB ya está instalado en la carpeta bin/.")
        return True

    print("[*] Iniciando descarga de Android Platform Tools (ADB) desde los servidores de Google...")
    os.makedirs(BIN_DIR, exist_ok=True)
    zip_path = os.path.join(BIN_DIR, "platform-tools.zip")

    try:
        # Descargar el archivo zip oficial de Google
        urllib.request.urlretrieve(ADB_ZIP_URL, zip_path, download_progress)
        print("\n[+] Descarga completada. Extrayendo archivos...")

        # Extraer el zip
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(BIN_DIR)

        # Eliminar el archivo zip temporal
        os.remove(zip_path)
        print("[+] ADB extraído con éxito en bin/platform-tools/.")
        return True
    except Exception as e:
        print(f"\n[-] ERROR al descargar/instalar ADB: {e}")
        return False

def configure_port_forward():
    if not os.path.exists(ADB_EXE):
        print("[-] ADB no está disponible. No se puede configurar la conexión USB.")
        return

    print("\n" + "="*60)
    print("           CONFIGURACIÓN DE CONEXIÓN USB (ADB)")
    print("="*60)
    print("1. Conecta tu celular Android a la PC mediante cable USB.")
    print("2. Asegúrate de tener activada la 'Depuración por USB' en tu celular:")
    print("   (Ajustes -> Sistema -> Opciones de desarrollador -> Depuración por USB).")
    print("3. Si tu celular te pide confirmación ('¿Permitir depuración por USB?'), presiona Aceptar.")
    print("="*60)
    input("[*] Presiona ENTER una vez que hayas conectado tu celular con la Depuración USB activa...")

    print("[*] Buscando dispositivos conectados...")
    try:
        # Listar dispositivos conectados
        devices_out = subprocess.check_output([ADB_EXE, "devices"]).decode("utf-8")
        print(devices_out)

        if "device\r" not in devices_out and "device\n" not in devices_out:
            print("[!] ADVERTENCIA: No se detectó ningún celular conectado en modo depuración.")
            print("    Verifica el cable USB, vuelve a activar la Depuración USB y asegúrate de dar los permisos en la pantalla del celular.")
            return

        print("[*] Configurando redirección de puertos (adb reverse)...")
        # adb reverse redirige localhost:8000 en el celular hacia localhost:8000 de la PC
        subprocess.run([ADB_EXE, "reverse", "tcp:8000", "tcp:8000"], check=True)
        print("[+] ¡Éxito! Redirección de puerto USB configurada.")
        print("\n👉 Ahora abre en tu celular Android:")
        print("   http://localhost:8000")
        print("\n(Asegúrate de que 'python server.py' esté corriendo en tu PC).")
        print("="*60)

    except subprocess.CalledProcessError as ce:
        print(f"[-] ERROR al ejecutar comandos de ADB: {ce}")
    except Exception as e:
        print(f"[-] ERROR inesperado: {e}")

if __name__ == "__main__":
    if setup_adb():
        configure_port_forward()
