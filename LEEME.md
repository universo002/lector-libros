# Lector — tus libros como audiolibros

App para iPhone hecha en Flutter. Abre PDF, EPUB y TXT, pensada para libros de más de 1000 páginas: los procesa en segundo plano y solo dibuja en pantalla lo que estás viendo. Los lee en voz alta incluso con la pantalla bloqueada y traduce libros en inglés al español dentro del celular, gratis.

## Qué hace

- **Biblioteca** con tapas de colores, progreso y tiempo restante de cada libro.
- **Lectura en segundo plano**: seguís escuchando con la pantalla apagada o usando otras apps. Los controles aparecen en la pantalla bloqueada, el Centro de control y los auriculares.
- **Voz natural en español de España** con las voces «Mejorada» y «Premium» del iPhone.
- **Traducción al español** de libros en inglés, sin internet (baja unos 30 MB la primera vez). Empieza por donde estás leyendo, así podés escuchar mientras traduce.
- **Resalta la palabra** que se está leyendo y sigue el texto sola.
- **Índice**, **buscador**, **marcadores** y **temporizador** (por minutos o al terminar el capítulo).
- **Velocidad** de 0,5× a 2×, **tamaño de letra** y temas **Claro**, **Sepia** y **Noche**.
- Recuerda dónde quedaste en cada libro.

---

# Instalarla en el iPhone sin Mac

Todo se hace desde tu compu con Windows. No hace falta tener Flutter instalado: lo compila Codemagic en una Mac en la nube.

Vas a necesitar:
- Tu compu con Windows
- El cable del iPhone
- Una cuenta de GitHub
- Tu Apple ID

## Parte 1 · Subir el proyecto a GitHub

1. En GitHub creá un repositorio nuevo, por ejemplo `lector-libros`. Puede ser **privado**.
2. Subí el contenido de esta carpeta: `lib/`, `pubspec.yaml`, `codemagic.yaml`, `.gitignore` y este `LEEME.md`. Lo podés hacer desde VS Code o con:
   ```bash
   cd lector_libros
   git init
   git add .
   git commit -m "Primera versión del lector"
   git branch -M main
   git remote add origin https://github.com/TU-USUARIO/lector-libros.git
   git push -u origin main
   ```

> El archivo `codemagic.yaml` tiene que quedar en la raíz del repositorio, al lado de `pubspec.yaml`.

## Parte 2 · Compilar en Codemagic

1. Entrá a **codemagic.io** y registrate con **GitHub** (plan gratis personal).
2. **Add application** › elegí GitHub › seleccioná `lector-libros` › tipo **Flutter App**.
3. Cuando pregunte la configuración, elegí **codemagic.yaml** (no el editor visual).
4. Tocá **Start new build**, elegí el workflow **iPhone para Sideloadly** y la rama `main`.
5. Esperá unos 10 a 15 minutos. Cuando termine en verde, en **Artifacts** descargá **Lector.ipa**.

Si termina en rojo, abrí el paso que falló, copiá las últimas líneas del error y mandámelas.

## Parte 3 · Preparar Windows (una sola vez)

1. Instalá **iTunes** e **iCloud** desde la página de Apple (apple.com), **no** desde Microsoft Store: Sideloadly necesita esas versiones.
2. Instalá **Sideloadly** desde su sitio oficial: **sideloadly.io**.
3. Conectá el iPhone con el cable, desbloquealo y tocá **Confiar** en este equipo.

## Parte 4 · Instalar la app

1. Abrí Sideloadly. Arriba tiene que aparecer tu iPhone.
2. Arrastrá **Lector.ipa** a la ventana.
3. En **Apple account** poné tu Apple ID y tocá **Start**. Te va a pedir tu contraseña y el código de verificación.
4. En el iPhone:
   - **Ajustes › General › VPN y gestión de dispositivos** › tocá tu Apple ID › **Confiar**.
   - **Ajustes › Privacidad y seguridad › Modo de desarrollador** › activalo (el celu se reinicia).
5. ¡Abrí **Lector**!

> **Seguridad:** Sideloadly usa tu Apple ID para firmar la app. Si preferís no poner tu cuenta principal, podés crear un Apple ID secundario solo para esto.

## Que no venza a los 7 días

Con un Apple ID gratis, la app deja de abrir a los 7 días. Para que se renueve sola:

1. En iTunes, con el iPhone conectado, activá **Sincronizar con este iPhone mediante Wi-Fi**.
2. En Sideloadly, antes de tocar Start, abrí **Advanced options** y marcá **Automatically refresh**.
3. Dejá Sideloadly abierto (queda en la bandeja de Windows). Cuando la compu y el celu estén en la misma Wi-Fi, renueva la app antes de que venza.

Si alguna vez vence igual, repetís la Parte 4 con el mismo `.ipa`. **Tus libros no se borran.**

## Cuando cambie el código

Subí los cambios a GitHub (`git add .`, `git commit`, `git push`), corré un build nuevo en Codemagic e instalá el `.ipa` nuevo con Sideloadly. Se instala encima y conserva tus libros.

El plan gratis de Codemagic trae 500 minutos por mes: alcanza para unas 30 compilaciones.

---

## Consejos de uso

- **Voz más humana:** en el iPhone, **Ajustes › Accesibilidad › Contenido leído › Voces › Español › España**, y descargá una voz que diga **Mejorada** o **Premium**. Después elegila en la app con el botón de voz.
- **Agregar libros:** el botón «Agregar libro» abre Archivos, así que podés traerlos de iCloud, Drive o Descargas.
- **Traducir:** en un libro largo tarda unos minutos y avanza mientras la app está abierta o leyendo en voz alta.
- Mantené apretado un párrafo para agregar un marcador, copiarlo o ver el original en inglés.
- Mantené apretados ⏪ ⏩ para saltar de capítulo.

## Lo que no puede leer

- **PDF escaneados** (fotos de páginas, sin texto seleccionable).
- **Libros con DRM** (Kindle, Google Play Libros, Apple Books comprados).
