# Guía de Despliegue en BlueHost (Rama DEV)

Este documento detalla el procedimiento seguro para desplegar la rama dev en el entorno de pruebas de BlueHost.

## 📍 Ruta de Despliegue Objetivo
/public_html/vegendigital/sistemas/contable/dev/

## ⚠️ Advertencia Importante
**NO** ejecutar git reset --hard sin haber realizado un respaldo previo de los archivos.

---

## 🛠️ Procedimiento de Despliegue Paso a Paso

1. **Conexión SSH:**
   Conéctate al servidor de BlueHost mediante SSH con tus credenciales:
   `ash
   ssh usuario@dominio.com
   `

2. **Navegación a la Carpeta:**
   Dirígete al directorio donde se encuentra alojada la aplicación de desarrollo:
   `ash
   cd /public_html/vegendigital/sistemas/contable/dev/
   `

3. **Verificación de Repositorio Git:**
   Asegúrate de que la carpeta es un repositorio válido:
   `ash
   git status
   `
   *(Debería confirmar que estás en un repositorio)*

4. **Verificación del Remote:**
   Confirma que el origen apunta al repositorio correcto en GitHub:
   `ash
   git remote -v
   `

5. **Verificación del Branch Activo:**
   Asegúrate de estar en la rama dev:
   ` ash
   git branch --show-current
   `
   *Si no estás en dev, cambia de rama con git checkout dev.*

6. **Respaldo Previo (Backup):**
   Antes de aplicar los cambios, crea un respaldo de la carpeta `dev` en un directorio superior seguro, excluyendo la carpeta oculta `.git`:
   ```bash
   cd /public_html/vegendigital/sistemas/contable/
   mkdir -p backups

   tar \
     --exclude='dev/.git' \
     --exclude='dev/backups' \
     -czf "backups/mica_dev_$(date +%Y%m%d_%H%M%S).tar.gz" \
     dev

   cd dev
   ```

7. **Estado Actual:**
   Verifica que no haya cambios locales sin commitear que puedan bloquear el pull:
   ` ash
   git status
   `

8. **Fetch desde Origin:**
   Trae los últimos cambios del repositorio remoto sin fusionarlos aún:
   ` ash
   git fetch origin
   `

9. **Actualización (Pull Fast-Forward):**
   Aplica los cambios de manera segura (solo si se puede hacer fast-forward):
   ` ash
   git pull --ff-only origin dev
   `

10. **Comprobación de Permisos:**
    Asegúrate de que los archivos tengan los permisos correctos para ser servidos por Apache (típicamente 644 para archivos y 755 para directorios):
    ` ash
    find . -type d -exec chmod 755 {} \;
    find . -type f -exec chmod 644 {} \;
    `

11. **Verificación de index.html:**
    Asegúrate de que el archivo index.html se encuentre en la raíz de esta carpeta y apunte correctamente a src/css/ y src/js/.

12. **Limpieza de Caché del Navegador:**
    Accede a la URL del sistema y borra caché (Ctrl+F5 o Cmd+Shift+R).

---

## 🔄 Procedimiento de Rollback

En caso de que el despliegue falle o la aplicación se rompa:

1. Dirígete al directorio superior y restaura los archivos desde el backup generado en el paso 6:
   ```bash
   cd /public_html/vegendigital/sistemas/contable/
   tar -xzf backups/mica_dev_YYYYMMDD_HHMMSS.tar.gz
   cd dev
   ```
   *(Reemplaza YYYYMMDD_HHMMSS con el timestamp correspondiente).*
2. Verifica la aplicación en el navegador nuevamente.
