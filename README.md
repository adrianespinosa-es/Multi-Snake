# Mult Snake

Snake 2 vs 2 para 4 jugadores en la misma pantalla (PC y móvil). Godot 4.3+ (GDScript).

## Cómo abrirlo
1. Abre Godot 4.3 o superior -> Importar -> selecciona `project.godot`.
2. Pulsa F5 para jugar.

## Reglas
- Partida de 2:00. Fase 1 (0:00-1:00): puntos de +1 cubo. Fase 2 (1:00-1:30): 1/5 de los puntos dan +2.
- Fase 3 (1:30-fin): aparecen cubos pared (matan), y cubos de velocidad -1/4 / +1/4 (1/5 de probabilidad).
- Chocar con borde, pared, cuerpo propio o ajeno = eliminado; reapareces a los 5 s en una zona libre.
- Equipos: AZUL = J1+J2, ROJO = J3+J4. Gana la suma de puntos más alta.

## Controles
- PC: J1 WASD, J2 TFGH, J3 IJKL, J4 flechas. Espacio/Enter para empezar.
- Móvil: desliza el dedo dentro de tu cuadrante (J1 arriba-izq, J2 abajo-izq, J3 arriba-der, J4 abajo-der).

## Parámetros fáciles de tocar (arriba de `main.gd`)
`GAME_TIME`, `PHASE2_AT`, `PHASE3_AT`, `BASE_STEP`, `SPEED_FACTOR`, `RESPAWN_TIME`, `MAX_WALLS`, `COLS/ROWS`.

## Exportar
Proyecto -> Exportar... -> añade preset Android (necesita Android SDK) o Windows/Linux/Mac/Web.

## Git: recuperar versiones
    git log --oneline            # ver versiones
    git checkout <hash> -- .     # volver a esa versión
    git checkout v0.1 -- .       # volver a la etiqueta v0.1
    git commit -am "mensaje"     # guardar nueva versión
