# Multi-Snake

Snake 2 vs 2 para 4 jugadores (PC y móvil). Godot 4.3+ (GDScript).

## Flujo
1. **Menú principal** con el nombre del juego (Multi-Snake), fondo 3D con serpientes y botones redondeados:
   Jugar online / Jugar offline (vs IA) / Salir.
2. **Perfil** (arriba a la derecha): icono + nombre. Al pulsarlo se cambia el nombre y la imagen entre 10
   avatares incluidos en `avatars/`. La primera vez se pide el nombre antes de poder jugar.
3. **Offline**: eliges color; tú + 1 IA contra 2 IA. Las IA usan colores distintos.
4. **Online**: uno crea la partida (anfitrión) y los otros 3 se unen con su IP. En la sala cada
   jugador elige color; los colores ocupados quedan deshabilitados (no se pueden repetir).
   El anfitrión pulsa "Empezar" (los huecos libres los ocupa la IA).

## Equipos
- Equipo 1 = huecos 1 y 2 (marcados con un cuadrado en la cabeza).
- Equipo 2 = huecos 3 y 4 (marcados con un aro en la cabeza).
- Gana el equipo con la suma de puntos más alta.

## Reglas de la partida (2:00)
- 0:00-1:00 puntos +1. 1:00-1:30: 1/5 de los puntos dan +2.
- 1:30-fin: aparecen cubos pared (matan) y cubos de velocidad -1/4 / +1/4 (1/5 de probabilidad).
- Chocar con borde, pared, cuerpo propio o ajeno = eliminado; reapareces a los 5 s en una zona libre.
- Al morir **pierdes todos tus puntos**, y se restan del total de tu equipo.

## Controles
- PC: flechas o WASD. Esc = salir al menú.
- Móvil: desliza el dedo por cualquier parte de la pantalla.

## Red (online)
- Puerto UDP 24567. En la misma WiFi/red local basta con la IP que muestra la sala del anfitrión.
- Por Internet el anfitrión debe abrir/redirigir el puerto UDP 24567 en su router.
- El anfitrión ejecuta la partida; si un jugador se desconecta, su serpiente pasa a la IA.

## Archivos
- `session.gd` (autoload): perfil, sala, colores únicos y red.
- `main.gd`: menú, perfil, offline, online y sala (tema redondeado).
- `menu_bg.gd`: fondo 3D animado del menú (serpientes, cubos flotantes).
- `avatars/avatar_01..10.png`: imágenes de perfil (puedes sustituirlas por las tuyas, 256x256 PNG).
- `game.gd`: partida, IA y dibujo.

## Git
    git log --oneline
    git checkout v0.1 -- .
    git add -A && git commit -m "mensaje"
