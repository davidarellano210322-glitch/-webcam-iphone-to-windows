import sys
import ctypes
import subprocess

def is_admin():
    try:
        return ctypes.windll.shell32.IsUserAnAdmin()
    except Exception:
        return False

def run_firewall_rule():
    print("=" * 60)
    print("        CONFIGURADOR DE RED Y FIREWALL - ANTIGRAVITY")
    print("=" * 60)
    
    # 1. Cambiar el tipo de red activa a Privada
    print("[*] Configurando perfil de red de Windows a 'Privado'...")
    try:
        # Obtener el nombre del perfil de red activo (por ejemplo: "Santa ana 2")
        profile_cmd = "Get-NetConnectionProfile | Select-Object -ExpandProperty Name"
        profile_name = subprocess.check_output(["powershell", "-Command", profile_cmd]).decode("utf-8").strip()
        
        if profile_name:
            print(f"[+] Red activa detectada: '{profile_name}'")
            # Cambiar a Privado
            set_private_cmd = f'Set-NetConnectionProfile -Name "{profile_name}" -NetworkCategory Private'
            subprocess.run(["powershell", "-Command", set_private_cmd], check=True)
            print("[+] Perfil de red cambiado a 'Privado' con éxito.")
        else:
            print("[-] No se detectó ninguna red activa para configurar.")
    except Exception as e:
        print(f"[-] No se pudo cambiar el perfil de red a Privado automáticamente: {e}")
        print("    (Puedes cambiarlo manualmente en la configuración de Wi-Fi de Windows).")
        
    # 2. Abrir puerto 8000 en el Firewall
    print("\n[*] Ejecutando regla de firewall para puerto 8000...")
    powershell_cmd = (
        'New-NetFirewallRule -DisplayName "Antigravity Webcam Server" '
        '-Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow'
    )
    
    try:
        result = subprocess.run(
            ["powershell", "-Command", powershell_cmd],
            capture_output=True,
            text=True,
            check=False
        )
        
        if result.returncode == 0:
            print("[+] ¡ÉXITO! El puerto 8000 se ha abierto en tu Firewall de Windows.")
        else:
            # Si ya existía la regla, Windows PowerShell devuelve un error, pero no pasa nada
            if "already exists" in result.stderr.lower() or "ya existe" in result.stderr.lower() or "0x80070057" in result.stderr.lower():
                print("[+] La regla de Firewall ya estaba creada.")
            else:
                print("[-] Error al crear la regla de Firewall:")
                print(result.stderr)
            
    except Exception as e:
        print(f"[-] Ocurrió un error inesperado al configurar el Firewall: {e}")
        
    print("\n" + "=" * 60)
    print("[!] Listo. Por favor, asegúrate de que tu iPhone esté conectado a este mismo WiFi.")
    print("=" * 60)
    input("Presiona ENTER para cerrar esta ventana...")

if __name__ == "__main__":
    if is_admin():
        run_firewall_rule()
    else:
        print("[*] Solicitando permisos de administrador en Windows...")
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
            print(f"[-] No se pudieron obtener permisos de administrador: {e}")
            input("Presiona ENTER para salir...")
