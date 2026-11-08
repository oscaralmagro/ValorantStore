# Valorant Store

App no oficial para Android e iOS, hecha con Flutter, para consultar tu tienda de Valorant y tu cuenta desde el móvil.

## Funciones

- **Tienda**: oferta diaria, colecciones, mercado nocturno y accesorios, con tu saldo de VP, RP y KC.
- **Armas**: todas las skins, con estilos, niveles, vídeos y precios.
- **Agentes**: agrupados por rol, con los que tienes y los que no, y sus habilidades.
- **Pase**: pase de temporada con tu nivel y progreso.
- **Esports**: partidos, equipos y Classic de equipos.
- **Perfil**: carrera, rango, rango por acto e historial de partidas con detalle de ambos equipos.
- Notificaciones de la tienda diaria.

## Descargas

Los instaladores están en [Releases](../../releases).

- **Android**: descarga el `.apk` y ábrelo.
- **iOS**: el `.ipa` no está firmado. Fírmalo con AltStore o Sideloadly.

## Compilar

El repositorio incluye dos workflows de GitHub Actions:

- `build.yml`: genera el APK de Android.
- `build-ios.yml`: genera el IPA sin firmar de iOS.

Para compilar:
1. Ve a **Actions**.
2. Elige **Build APK** o **Build iOS** y pulsa **Run workflow**.
3. Descarga el archivo desde **Artifacts**.

Los archivos que necesita el workflow en la raíz del repo son `main.dart`, `pubspec.yaml`, `icon.png` e `icon_fg.png`.

## Limitaciones

- Usa endpoints no oficiales de Riot, que pueden cambiar o dejar de funcionar sin aviso.
- Riot solo devuelve el rango de los últimos actos, no de todos.
- Los Pick'Ems y Premier no están disponibles.
- No está probada en iPhone real.

## Privacidad

Tu sesión se guarda en el almacenamiento seguro del dispositivo. La app no usa servidores propios ni envía tus datos a terceros.

## Aviso legal

Valorant Store no está afiliada, respaldada ni patrocinada por Riot Games. Valorant y Riot Games son marcas registradas de Riot Games, Inc.
