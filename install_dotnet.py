import sys
import ctypes
import subprocess

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except Exception:
        return False

def run_install():
    print("=" * 60)
    print("        INSTALADOR AUTOMÁTICO DE .NET SDK 8.0")
    print("=" * 60)
    print("[*] Iniciando instalación de .NET SDK 8.0 por winget...")
    
    # Ejecutamos winget para instalar el SDK de dotnet. Al estar como Admin, se ejecutará sin restricciones
    cmd = "winget install Microsoft.DotNet.SDK.8 --accept-package-agreements --accept-source-agreements"
    try:
        result = subprocess.run(["powershell", "-Command", cmd], check=False)
        if result.returncode == 0:
            print("\n[+] ¡ÉXITO! .NET SDK 8.0 se ha instalado correctamente.")
        else:
            print(f"\n[-] Error al instalar: código de salida {result.returncode}")
    except Exception as e:
        print(f"[-] Ocurrió un error inesperado: {e}")
        
    print("=" * 60)
    input("Presiona ENTER para finalizar...")

if __name__ == "__main__":
    if is_admin():
        run_install()
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
