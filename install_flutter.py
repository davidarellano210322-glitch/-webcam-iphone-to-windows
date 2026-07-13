import os
import sys
import json
import urllib.request
import zipfile
import winreg
import ctypes
import subprocess

FLUTTER_RELEASES_URL = "https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json"
INSTALL_DIR = r"C:\src"
ZIP_PATH = os.path.join(INSTALL_DIR, "flutter.zip")
FLUTTER_PATH = os.path.join(INSTALL_DIR, "flutter")
FLUTTER_BIN = os.path.join(FLUTTER_PATH, "bin")

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except Exception:
        return False

def download_progress(block_num, block_size, total_size):
    read_so_far = block_num * block_size
    if total_size > 0:
        percent = min(100, (read_so_far * 100) / total_size)
        sys.stdout.write(f"\rDescargando Flutter SDK: {percent:.1f}% ({read_so_far // 1048576} MB / {total_size // 1048576} MB)")
    else:
        sys.stdout.write(f"\rDescargando Flutter SDK: {read_so_far // 1048576} MB")
    sys.stdout.flush()

def get_latest_flutter_release():
    print("[*] Obteniendo lista de versiones estables de Flutter...")
    try:
        with urllib.request.urlopen(FLUTTER_RELEASES_URL) as response:
            data = json.loads(response.read().decode())
        
        base_url = data["base_url"]
        current_stable_hash = data["current_release"]["stable"]
        
        # Buscar el archivo correspondiente al hash estable
        for release in data["releases"]:
            if release["hash"] == current_stable_hash and release["channel"] == "stable":
                archive = release["archive"]
                version = release["version"]
                download_url = f"{base_url}/{archive}"
                return download_url, version
        
        # Fallback a la primera versión estable en la lista
        for release in data["releases"]:
            if release["channel"] == "stable":
                return f"{base_url}/{release['archive']}", release["version"]
                
    except Exception as e:
        print(f"[-] Error obteniendo versiones de Flutter: {e}")
    
    # URL de fallback rígido si falla la red JSON
    return "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.22.2-stable.zip", "3.22.2"

def add_to_system_path(path_to_add):
    print(f"[*] Registrando '{path_to_add}' en el PATH de Windows...")
    try:
        # Abrir la clave del registro del Entorno del Usuario
        key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_ALL_ACCESS)
        try:
            # Obtener el valor actual de PATH
            try:
                path_val, _ = winreg.QueryValueEx(key, "Path")
            except FileNotFoundError:
                path_val = ""
            
            # Limpiar rutas para comparación
            paths = [p.strip().rstrip('\\') for p in path_val.split(";")]
            cleaned_target = path_to_add.rstrip('\\')
            
            if cleaned_target not in paths:
                new_path_val = path_val + ";" + path_to_add if path_val else path_to_add
                winreg.SetValueEx(key, "Path", 0, winreg.REG_EXPAND_SZ, new_path_val)
                print(f"[+] ¡Éxito! Ruta agregada al registro de Windows.")
                
                # Notificar al sistema del cambio de variables de entorno
                # HWND_BROADCAST=0xFFFF, WM_SETTINGCHANGE=0x001A
                try:
                    ctypes.windll.user32.SendMessageTimeoutW(0xFFFF, 0x001A, 0, "Environment", 2, 5000, ctypes.byref(ctypes.c_long()))
                except Exception:
                    pass
            else:
                print(f"[+] La ruta ya se encuentra configurada en el PATH.")
        finally:
            winreg.CloseKey(key)
    except Exception as e:
        print(f"[-] Error al modificar la variable PATH en el registro: {e}")

def run_installation():
    print("=" * 60)
    print("        INSTALADOR AUTOMÁTICO DE FLUTTER SDK - WINDOWS")
    print("=" * 60)
    
    # 1. Crear carpeta destino
    os.makedirs(INSTALL_DIR, exist_ok=True)
    
    if os.path.exists(os.path.join(FLUTTER_BIN, "flutter.bat")):
        print(f"[+] Flutter ya se encuentra instalado en: {FLUTTER_PATH}")
        add_to_system_path(FLUTTER_BIN)
        verify_flutter()
        return

    # 2. Obtener enlace
    download_url, version = get_latest_flutter_release()
    print(f"[+] Versión estable detectada: {version}")
    print(f"[+] URL de descarga: {download_url}")
    
    # 3. Descargar SDK
    print("[*] Iniciando descarga del SDK (esto pesa aprox. 1 GB y puede demorar unos minutos)...")
    try:
        urllib.request.urlretrieve(download_url, ZIP_PATH, download_progress)
        print("\n[+] Descarga finalizada con éxito.")
    except Exception as e:
        print(f"\n[-] Error en la descarga del zip: {e}")
        if os.path.exists(ZIP_PATH):
            os.remove(ZIP_PATH)
        return

    # 4. Extraer el zip
    print("[*] Extrayendo archivos en C:\\src\\... (Esto puede tomar un momento)")
    try:
        with zipfile.ZipFile(ZIP_PATH, 'r') as zip_ref:
            # Extraer en C:\src. El zip incluye la carpeta interna 'flutter/'
            zip_ref.extractall(INSTALL_DIR)
        print("[+] Extracción completada.")
    except Exception as e:
        print(f"[-] Error durante la extracción: {e}")
        return
    finally:
        # Eliminar zip temporal
        if os.path.exists(ZIP_PATH):
            os.remove(ZIP_PATH)

    # 5. Agregar a PATH
    add_to_system_path(FLUTTER_BIN)
    
    # 6. Verificar
    verify_flutter()

def verify_flutter():
    print("\n[*] Verificando instalación de Flutter...")
    # Agregar temporalmente al PATH del proceso actual para probar
    os.environ["PATH"] = FLUTTER_BIN + ";" + os.environ["PATH"]
    
    try:
        result = subprocess.run(["flutter", "--version"], capture_output=True, text=True, check=False)
        if result.returncode == 0:
            print("\n[+] ¡FLUTTER INSTALADO CON ÉXITO!")
            print(result.stdout.strip())
            print("\nNota: Para usar el comando 'flutter' en tus consolas abiertas, deberás cerrarlas y abrirlas de nuevo.")
        else:
            print(f"[-] Error al validar flutter cli: {result.stderr}")
    except Exception as e:
        print(f"[-] No se pudo ejecutar el comando de verificación: {e}")

    print("=" * 60)
    input("Presiona ENTER para finalizar...")

if __name__ == "__main__":
    if is_admin():
        run_installation()
    else:
        print("[*] Solicitando permisos de administrador...")
        try:
            ctypes.windll.shell32.ShellExecuteW(
                None, 
                "runas", 
                sys.executable, 
                f'"{__file__}"', 
                None, 
                1
            )
        except Exception as e:
            print(f"[-] Error al solicitar permisos de administrador: {e}")
            input("Presiona ENTER para salir...")
