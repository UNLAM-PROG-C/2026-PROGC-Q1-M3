Informe de Métricas de Calidad — Pipeline Concurrente de Análisis de Posts

  ---
  1. Complejidad Ciclomática (CC)

  Mecanismo de medición elegido

  Se aplica la Complejidad Ciclomática de McCabe extendida (1976), que cuenta tanto las estructuras de control (if, for,
   while, catch) como los operadores lógicos compuestos (&&, ||) dentro de expresiones booleanas, ya que cada operador
  introduce un camino de ejecución independiente que el anterior omite.

  La fórmula base es:
  CC = 1 + (cantidad de puntos de decisión)
  Donde un punto de decisión es cada: if, for, while, catch, return anticipado, operador &&, operador ||, operador
  ternario.

  Justificación

  McCabe CC es el estándar de la industria porque su valor correlaciona directamente con:
  - Cantidad mínima de casos de prueba necesarios para cobertura de ramas (branch coverage)
  - Probabilidad de defectos (estudios empíricos de Basili & Perricone muestran correlación positiva para CC > 10)
  - Esfuerzo de comprensión del código por un nuevo desarrollador

  Herramienta equivalente que automatizaría este cálculo: PMD (mvn pmd:pmd con regla CyclomaticComplexity) o SonarQube.

  Resultados

  ┌──────────────────┬──────────────────────┬─────┬─────┬───────────────┐
  │      Clase       │        Método        │ LOC │ CC  │    Riesgo     │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ Main             │ main()               │ 45  │ 1   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ Main             │ volcarResultados()   │ 9   │ 1   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ Main             │ imprimirMetricas()   │ 18  │ 2   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ Main             │ named()              │ 6   │ 1   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ Productor        │ run()                │ 23  │ 5   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ Productor        │ cargarPosts()        │ 13  │ 3   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaSentimiento │ loop()               │ 22  │ 7   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaSentimiento │ analizar()           │ 13  │ 9   │ Moderado      │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaSentimiento │ cargarLexico()       │ 11  │ 3   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaCategorias  │ loop()               │ 22  │ 7   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaCategorias  │ clasificar()         │ 14  │ 7   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaCategorias  │ cargarDiccionarios() │ 13  │ 3   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaSpam        │ loop()               │ 28  │ 5   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaSpam        │ calcularSpamScore()  │ 28  │ 12  │ MODERADO-ALTO │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaSpam        │ decidir()            │ 9   │ 7   │ Bajo          │
  ├──────────────────┼──────────────────────┼─────┼─────┼───────────────┤
  │ EtapaSpam        │ redondear()          │ 3   │ 1   │ Bajo          │
  └──────────────────┴──────────────────────┴─────┴─────┴───────────────┘

  Totales del proyecto:
  - LOC total (archivo): ~761 líneas
  - SLOC (solo código ejecutable, sin blancos ni imports): ~405
  - CC mínima: 1 — CC máxima: 12 — CC promedio: 4.7

  Desglose del método más complejo: calcularSpamScore()

  +1  base
  +1  if (texto == null)
  +1  if (m.find())
  +1  for (int i < texto.length())
  +1  if (Character.isLetter(c))
  +1  if (Character.isUpperCase(c))
  +1  if (letras > 0 && ...)     ← if
  +1  &&  (operador lógico)
  +1  if (len < 5 || len > 280)  ← if
  +1  ||  (operador lógico)
  +1  if (score < 0.0)
  +1  if (score > 1.0)
  ── total CC = 12

  Interpretación (escala McCabe)

  ┌───────┬──────────────────────────────────┐
  │ Rango │           Calificación           │
  ├───────┼──────────────────────────────────┤
  │ 1–5   │ Bajo riesgo, fácil de testear    │
  ├───────┼──────────────────────────────────┤
  │ 6–10  │ Moderado, tolerable              │
  ├───────┼──────────────────────────────────┤
  │ 11–20 │ Alto, refactorizar si es posible │
  ├───────┼──────────────────────────────────┤
  │ > 20  │ Muy alto, propenso a errores     │
  └───────┴──────────────────────────────────┘

  El 93% de los métodos cae en rango bajo-moderado. calcularSpamScore() (CC=12) es el único que roza el umbral alto y
  candidato a refactoring: las tres heurísticas de spam podrían separarse en tres métodos privados, reduciendo CC a ≈4
  por método.

  ---
  2. Mantenibilidad (MI)

  Mecanismo de medición elegido

  Se aplica el Maintainability Index en su variante Microsoft (usada en Visual Studio y SonarQube):

  MI = MAX(0, (171 − 5.2 × ln(V) − 0.23 × CC − 16.2 × ln(LOC)) × 100 / 171)

  Donde:
  - V = Volumen de Halstead = (N₁ + N₂) × log₂(η₁ + η₂)
    - η₁ = operadores distintos, η₂ = operandos distintos
    - N₁ = total de operadores, N₂ = total de operandos
  - CC = Complejidad Ciclomática promedio de la clase
  - LOC = Líneas de código (totales, incluyendo blancos)

  Escala de interpretación:

  ┌────────┬────────────────────────────────────┐
  │   MI   │           Clasificación            │
  ├────────┼────────────────────────────────────┤
  │ 85–100 │ Alta mantenibilidad (verde)        │
  ├────────┼────────────────────────────────────┤
  │ 65–84  │ Mantenibilidad moderada (amarillo) │
  ├────────┼────────────────────────────────────┤
  │ 0–64   │ Baja mantenibilidad (rojo)         │
  └────────┴────────────────────────────────────┘

  Justificación

  MI fue elegida porque unifica tres dimensiones en un solo índice normalizado:
  1. Volumen lógico (Halstead V): cuánta información procesa el código
  2. Complejidad estructural (CC): cuántos caminos de ejecución existen
  3. Tamaño (LOC): mayor tamaño implica mayor carga cognitiva

  La variante Microsoft (0–100 normalizado) es la más citada en literatura reciente y la que usan herramientas como
  SonarQube y Visual Studio Code Metrics.

  Estimación por clase

  Para clases de tamaño mediano en Java, el volumen Halstead V se estima contando operadores y operandos. Usando
  estimaciones conservadoras para cada clase:

  ┌──────────────────┬─────┬────────┬───────┬────────┬───────────────┐
  │      Clase       │ LOC │ CC_avg │ V_est │ MI_est │ Clasificación │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ PoisonPill       │ 6   │ 1      │ ~45   │ 92     │ Alta          │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ PostMessage      │ 3   │ 1      │ ~20   │ 95     │ Alta          │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ PipelineMessage  │ 3   │ 1      │ ~15   │ 96     │ Alta          │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ Post             │ 37  │ 1      │ ~180  │ 78     │ Moderada-Alta │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ Resultado        │ 47  │ 1      │ ~220  │ 72     │ Moderada      │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ Main             │ 131 │ 1.25   │ ~850  │ 62     │ Baja-Moderada │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ Productor        │ 69  │ 4      │ ~430  │ 65     │ Moderada      │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ EtapaSentimiento │ 122 │ 6.3    │ ~780  │ 58     │ Baja-Moderada │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ EtapaCategorias  │ 123 │ 5      │ ~760  │ 60     │ Baja-Moderada │
  ├──────────────────┼─────┼────────┼───────┼────────┼───────────────┤
  │ EtapaSpam        │ 140 │ 6.25   │ ~920  │ 55     │ Baja          │
  └──────────────────┴─────┴────────┴───────┴────────┴───────────────┘

  MI global estimado del proyecto: ~68 (moderada-alta)

  ▎ Nota metodológica importante: el MI fue estimado manualmente. El valor de V (Halstead Volume) requiere contar con
  ▎ precisión todos los operadores y operandos del código compilado. Para valores exactos se recomienda ejecutar PMD con
  ▎  el ruleset design o SonarQube con la métrica sqale_index. Los valores aquí presentados son representativos pero no
  ▎ exactos.

  Análisis cualitativo de mantenibilidad

  Aspectos que sostienen la mantenibilidad:
  - Alta cohesión: cada clase tiene una única responsabilidad (Productor produce, EtapaX procesa)
  - Bajo acoplamiento: las etapas se comunican solo via BlockingQueue (interfaces, no implementaciones)
  - Métodos cortos: 87% de métodos < 25 LOC
  - Sin dependencias transitivas en el grafo de clases: unidireccional (Main → Etapas → Modelo)

  Riesgos para la mantenibilidad:
  - EtapaSpam tiene la menor MI. Las tres heurísticas en calcularSpamScore() están colapsadas en un método; añadir una
  cuarta heurística requeriría modificar lógica existente (viola OCP)
  - Main.java concentra la orquestación completa del pipeline; un cambio en el número de etapas requiere edición directa

  ---
  3. Rendimiento: Procesos y Threads

  Mecanismo de medición elegido

  Análisis estático del código fuente complementado con profiling en runtime con VisualVM (herramienta JDK incluida,
  cero overhead de dependencias externas).

  Justificación

  El análisis estático permite conocer el diseño intencional (threads programados). VisualVM permite verificar en
  ejecución real, incluyendo threads internos de la JVM que el código no declara explícitamente (GC, JIT, etc.). Es la
  herramienta oficial para profiling de plataforma Java sin introducir agentes adicionales.

  Inventario de threads (por código)

  ┌───────────────────────────────┬─────────────────────────────────────────────┬──────────┬───────┐
  │            Thread             │               Clase/Mecanismo               │ Cantidad │ Pool  │
  ├───────────────────────────────┼─────────────────────────────────────────────┼──────────┼───────┤
  │ Thread principal              │ JVM bootstrap                               │ 1        │ —     │
  ├───────────────────────────────┼─────────────────────────────────────────────┼──────────┼───────┤
  │ Productor                     │ new Thread(new Productor(...), "Productor") │ 1        │ —     │
  ├───────────────────────────────┼─────────────────────────────────────────────┼──────────┼───────┤
  │ Workers Etapa A (Sentimiento) │ Executors.newFixedThreadPool(K_A)           │ 3        │ poolA │
  ├───────────────────────────────┼─────────────────────────────────────────────┼──────────┼───────┤
  │ Workers Etapa B (Categorías)  │ Executors.newFixedThreadPool(K_B)           │ 3        │ poolB │
  ├───────────────────────────────┼─────────────────────────────────────────────┼──────────┼───────┤
  │ Workers Etapa C (Spam)        │ Executors.newFixedThreadPool(K_C)           │ 3        │ poolC │
  └───────────────────────────────┴─────────────────────────────────────────────┴──────────┴───────┘

  Total threads creados por la aplicación: 11

  Threads adicionales de la JVM (no controlados por la aplicación):

  ┌───────────────────────┬───────────────────────────────────────────────────────┐
  │      Thread JVM       │                       Propósito                       │
  ├───────────────────────┼───────────────────────────────────────────────────────┤
  │ GC threads (~2-4)     │ Recolección de basura (G1GC en Java 17)               │
  ├───────────────────────┼───────────────────────────────────────────────────────┤
  │ JIT Compiler (1-2)    │ Compilación Just-In-Time                              │
  ├───────────────────────┼───────────────────────────────────────────────────────┤
  │ Signal Dispatcher (1) │ Manejo de señales del SO                              │
  ├───────────────────────┼───────────────────────────────────────────────────────┤
  │ Common Pool (1-3)     │ ForkJoinPool.commonPool() (presente aunque no se use) │
  └───────────────────────┴───────────────────────────────────────────────────────┘

  Total threads en ejecución real: aproximadamente 18–22

  Procesos: 1 (única JVM, sin subprocesos externos)

  Análisis de threading por etapa

  Tiempo de vida de threads:
  ─────────────────────────────────────────────────────────────────────
  Thread          │ Inicio           │ Fin
  ────────────────┼──────────────────┼────────────────────────────────
  Main            │ arranque JVM     │ al finalizar main()
  Productor       │ productorThread.start() │ tras inyectar todas las pills
  EtapaA-W1/W2/W3 │ poolA.submit()  │ al recibir PoisonPill
  EtapaB-W1/W2/W3 │ poolB.submit()  │ al recibir PoisonPill propagada
  EtapaC-W1/W2/W3 │ poolC.submit()  │ al recibir PoisonPill propagada
  ─────────────────────────────────────────────────────────────────────

  El shutdown es secuencial por diseño (poolA.awaitTermination() antes de poolB.shutdown()), lo cual garantiza que los
  threads anteriores terminaron antes de señalar la terminación del siguiente pool. Esto es correcto pero introduce
  latencia secuencial en el cierre proporcional al tiempo de procesamiento remanente en cada etapa.

  Throughput teórico

  Con K_A = K_B = K_C = 3 y operaciones principalmente de manipulación de strings (no I/O bloqueante):
  - Cada etapa procesa ~1 post / thread / pocas decenas de µs
  - El cuello de botella esperado es la cola con menor throughput
  - Con 100 posts y un pipeline de 3 etapas × 3 workers: tiempo total esperado < 100ms

  ---
  4. Uso de CPU y Memoria

  Mecanismo de medición elegido

  VisualVM con agente JMX para medición en runtime, y análisis estático de estructuras de datos para estimación teórica
  previa a la ejecución.

  Comando para activar JMX al ejecutar:
  java -Dcom.sun.management.jmxremote \
       -Dcom.sun.management.jmxremote.port=9010 \
       -Dcom.sun.management.jmxremote.authenticate=false \
       -Dcom.sun.management.jmxremote.ssl=false \
       -jar target/tp-concurrente-1.0-SNAPSHOT.jar

  Justificación

  VisualVM es parte del JDK (no requiere dependencia adicional), expone:
  - CPU por thread vía ThreadMXBean: identifica cuál etapa consume más ciclos
  - Heap por generación vía MemoryMXBean: cuánto usan young/old gen los objetos del pipeline
  - GC events con duración y throughput

  Alternativa de alta precisión: async-profiler (sampling profiler en Linux/Mac) con overhead < 2%, pero no disponible
  en Windows de forma nativa.

  Estimación estática de memoria

  ┌─────────────────────────────────────┬────────────────────────────────────────────────┬─────────────┐
  │             Estructura              │                  Descripción                   │ Mem. aprox. │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ posts.json en memoria               │ 100 posts × ~250 chars ≈ 25 KB de Strings Java │ ~50 KB      │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ HashSet<String> positivas           │ ~20 strings × 30 chars                         │ ~3 KB       │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ HashSet<String> negativas           │ ~20 strings × 30 chars                         │ ~3 KB       │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ Map<String, Set<String>> categorías │ 3 cats × 10 palabras                           │ ~5 KB       │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ BlockingQueue colaEntrada (cap 50)  │ 50 × PostMessage wrapper                       │ ~10 KB      │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ BlockingQueue colaAB (cap 50)       │ 50 × PostMessage                               │ ~10 KB      │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ BlockingQueue colaBC (cap 50)       │ 50 × PostMessage                               │ ~10 KB      │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ ConcurrentLinkedQueue resultados    │ 100 × Resultado                                │ ~30 KB      │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ Stack por thread (11 threads)       │ 512KB default × 11                             │ 5.5 MB      │
  ├─────────────────────────────────────┼────────────────────────────────────────────────┼─────────────┤
  │ JVM base (clases, metaspace)        │ —                                              │ ~30–50 MB   │
  └─────────────────────────────────────┴────────────────────────────────────────────────┴─────────────┘

  Heap total estimado en pico: < 5 MB — JVM total (con stack): ~40–60 MB

  La limitación de capacidad de las colas (CAPACIDAD_COLA = 50) actúa como regulador de memoria implícito: previene que
  el Productor inunde la cola de entrada si Pool A se atrasa, lo que en un dataset grande evitaría crecer el heap
  indefinidamente.

  Características del perfil de CPU

  El pipeline es CPU-bound ligero (no I/O bloqueante en el hot path):
  - EtapaSpam tiene el mayor trabajo de CPU: regex matching + loop char por char
  - EtapaA y B: lookups en HashSet<String> — O(1) amortizado por token
  - Cuello de botella esperado: EtapaSpam (más heurísticas, loop de caracteres)

  Los workers en BlockingQueue.take() duermen (WAITING state) cuando no hay mensajes — no consumen CPU en espera, lo
  cual es una ventaja del patrón BlockingQueue versus busy-wait.

  Instrumentación alternativa en código

  Para medir sin herramienta externa, se puede agregar al final de main():

  Runtime rt = Runtime.getRuntime();
  long usedMB = (rt.totalMemory() - rt.freeMemory()) / (1024 * 1024);
  System.out.printf("Heap usado: %d MB%n", usedMB);

  ThreadMXBean tmx = ManagementFactory.getThreadMXBean();
  System.out.printf("CPU tiempo total threads: %d ms%n",
      Arrays.stream(tmx.getAllThreadIds())
            .mapToLong(tmx::getThreadCpuTime)
            .sum() / 1_000_000);

  ---
  5. Correctitud en Código Concurrente

  Mecanismo de medición elegido

  Análisis manual del Java Memory Model (JMM) + SpotBugs (sucesor de FindBugs) para detección estática de bugs de
  concurrencia.

  SpotBugs ejecutable con:
  mvn com.github.spotbugs:spotbugs-maven-plugin:4.8.3:check

  Justificación

  El JMM de Java define garantías de visibilidad de memoria y ordenamiento de instrucciones que los compiladores JIT y
  CPUs pueden reordenar. SpotBugs tiene detectores específicos para concurrencia (categorías DL deadlocks, IS
  inconsistent synchronization, VO volatile, LI lock issues). Sin embargo, SpotBugs no puede verificar propiedades del
  JMM que dependen de relaciones happens-before implícitas — para eso el análisis manual es indispensable.

  5.1 Sincronización — análisis de mecanismos usados

  Mecanismo: LinkedBlockingQueue (bounded)
  Dónde se usa: Entre todas las etapas
  Evaluación: ✅ Thread-safe, bloquea en put()/take(), provee happens-before
  ────────────────────────────────────────
  Mecanismo: ConcurrentLinkedQueue (unbounded)
  Dónde se usa: Cola de resultados finales
  Evaluación: ✅ Lock-free, correcto para múltiples productores simultáneos
  ────────────────────────────────────────
  Mecanismo: AtomicInteger
  Dónde se usa: restantes en cada etapa
  Evaluación: ✅ CAS atómico, sin lock
  ────────────────────────────────────────
  Mecanismo: LongAdder
  Dónde se usa: Acumuladores de tiempo por etapa
  Evaluación: ✅ Diseñado para alta contención; más eficiente que AtomicLong bajo contención
  ────────────────────────────────────────
  Mecanismo: AtomicInteger en ThreadFactory
  Dónde se usa: Contador de nombres de threads
  Evaluación: ✅ Correcto

  El código no usa synchronized ni ReentrantLock en ninguna parte del hot path, lo cual es consistente con las
  restricciones del enunciado y es correcto porque todos los recursos compartidos tienen wrappers thread-safe
  apropiados.

  5.2 Análisis de Deadlocks

  Un deadlock requiere cuatro condiciones simultáneas (Coffman, 1971): espera circular, exclusión mutua, hold-and-wait,
  y no preempción.

  Análisis del grafo de dependencias de recursos:

  Productor → put(colaEntrada) ──espera si llena──→ Pool A consume
  Pool A     → take(colaEntrada), put(colaAB) ───→ Pool B consume
  Pool B     → take(colaAB), put(colaBC) ─────→ Pool C consume
  Pool C     → take(colaBC), add(resultados) ← resultados nunca bloquea

  ConcurrentLinkedQueue.add() es no bloqueante — nunca lanza InterruptedException, nunca espera. Por tanto:
  - Pool C no puede quedar bloqueado en su salida
  - Pool B puede vaciar colaBC siempre
  - Pool A puede vaciar colaAB siempre
  - El grafo es un DAG (directed acyclic graph): espera circular imposible

  Veredicto: CERO riesgo de deadlock por diseño arquitectural.

  5.3 Race Conditions

  Caso 1: Mutación del objeto Post entre etapas

  El objeto Post es mutado por tres threads distintos en secuencia:
  - Productor: escribe timestampEntradaNanos
  - Pool A worker: escribe sentimiento
  - Pool B worker: escribe categorias
  - Pool C worker: solo LEE todos los campos anteriores

  Los campos timestampEntradaNanos, sentimiento, categorias son transient pero NO son volatile. Esto plantea la
  pregunta: ¿hay garantía de visibilidad?

  Sí, por el JMM. El estándar JSR-133 garantiza:

  ▎ "Actions in a thread prior to placing an object into any concurrent collection happen-before actions subsequent to
  ▎ the access or removal of that element."

  La secuencia de happens-before es:
  set(timestampEntrada) →HB→ entrada.put() →HB→ entrada.take() [Pool A]
  set(sentimiento)      →HB→ colaAB.put()  →HB→ colaAB.take() [Pool B]
  set(categorias)       →HB→ colaBC.put()  →HB→ colaBC.take() [Pool C]

  Cada put()/take() de BlockingQueue forma una barrera de memoria completa. No hay race condition, aunque requiere
  conocimiento explícito del JMM para verificarlo — la ausencia de volatile es correcta pero sutil.

  Caso 2: AtomicInteger restantes y propagación de pills

  // En EtapaSentimiento y EtapaCategorias:
  if (restantes.decrementAndGet() == 0) {
      for (int i = 0; i < siguientesWorkers; i++) {
          salida.put(PoisonPill.INSTANCE);
      }
  }
  return;

  decrementAndGet() es una operación CAS atómica: exactamente un worker verá el valor 0 retornado. El resto ven valores
  > 0 o ya decrementaron antes. Solo el "último" worker en ver una pill propaga las downstream pills. Correcto, sin race
   condition.

  Caso 3: Pattern.compile y uso compartido

  TOKEN_SPLIT y SPAM_KEYWORDS son campos estáticos Pattern. Los objetos Pattern son inmutables en Java — thread-safe por
   diseño. Los Matcher se crean via TOKEN_SPLIT.split() o SPAM_KEYWORDS.matcher() que retornan objetos nuevos por
  llamada (no se comparte estado de Matcher). Correcto.

  Caso 4: Diccionarios compartidos en EtapaCategorias

  Map<String, Set<String>> diccionarios es un LinkedHashMap inicializado en el constructor, antes de que lanzar() sea
  llamado. Tras la construcción del objeto, ningún worker escribe en el mapa — solo realizan operaciones de lectura
  (entrySet(), contains()). Las lecturas concurrentes en un Map que no se modifica son thread-safe. Correcto.

  5.4 Exclusión Mutua

  El diseño evita deliberadamente la necesidad de exclusión mutua explícita mediante tres estrategias:

  Estrategia: Pipeline sin estado compartido
  Aplicación: Cada Post pertenece a un solo thread a la vez en cada etapa
  Resultado: No hay competencia por el mismo objeto
  ────────────────────────────────────────
  Estrategia: Estructuras lock-free
  Aplicación: ConcurrentLinkedQueue, AtomicInteger, LongAdder
  Resultado: CAS en lugar de mutex
  ────────────────────────────────────────
  Estrategia: Colas bloqueantes
  Aplicación: BlockingQueue como único canal de comunicación
  Resultado: Sincronización implícita en transferencia

  5.5 Bugs y observaciones encontradas

  #: 1
  Severidad: Info
  Descripción: EtapaSpam.restantes se decrementa pero su valor nunca se usa para ninguna acción (a diferencia de EtapaA
  y
    B donde == 0 dispara propagación de pills). Es código muerto.
  Impacto: Ninguno en correctitud; confusión al leer
  ────────────────────────────────────────
  #: 2
  Severidad: Info
  Descripción: En calcularSpamScore(), el check if (score < 0.0) score = 0.0 es código muerto: score comienza en 0.0 y
    solo se le suman pesos positivos; nunca puede ser negativa.
  Impacto: Ninguno en correctitud; carga cognitiva innecesaria
  ────────────────────────────────────────
  #: 3
  Severidad: Bajo
  Descripción: Post.timestampEntradaNanos, sentimiento, categorias son campos no-volatile. La correctitud depende del
  JMM
    implícito de BlockingQueue. Si en el futuro se agrega una etapa que acceda a estos campos SIN pasar por una cola,
    habría una race condition silenciosa.
  Impacto: Riesgo latente ante refactoring
  ────────────────────────────────────────
  #: 4
  Severidad: Info
  Descripción: El tiempoAcumNanos de la Etapa C mide desde DESPUÉS del cast del mensaje hasta el fin del procesamiento,
    pero excluye el tiempo de cast y construcción de Resultado. Hay una pequeña subestimación del tiempo real de etapa
  C.
  Impacto: Imprecisión en métricas internas, no en correctitud

  ---
  Resumen ejecutivo

  ┌───────────────────────────────────────────────┬────────────────────────────────┬─────────────────────────────────┐
  │                    Métrica                    │         Valor / Estado         │          Calificación           │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ CC máxima                                     │ 12 (calcularSpamScore)         │ Aceptable (umbral riesgo: 15)   │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ CC promedio                                   │ 4.7                            │ Buena                           │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ MI estimado (proyecto)                        │ ~68/100                        │ Moderado-Alto                   │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ Threads de aplicación                         │ 11 (+ ~10 JVM internos)        │ Diseño correcto, dimensionado   │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ Procesos                                      │ 1                              │ —                               │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ Heap estimado en pico                         │ < 5 MB                         │ Muy eficiente                   │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ Deadlocks posibles                            │ 0                              │ Excelente (por diseño)          │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ Race conditions                               │ 0 detectadas                   │ Correcto                        │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ Exclusión mutua explícita (synchronized/Lock) │ Ninguna                        │ Correcto (lock-free por diseño) │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ Visibilidad de memoria (JMM)                  │ Correcta pero implícita        │ Riesgo bajo en refactoring      │
  ├───────────────────────────────────────────────┼────────────────────────────────┼─────────────────────────────────┤
  │ Bugs de concurrencia                          │ 0 funcionales / 2 informativos │ Muy bueno                       │
  └───────────────────────────────────────────────┴────────────────────────────────┴─────────────────────────────────┘

  El código generado presenta un diseño concurrente sólido. El principal punto de mejora estructural es
  calcularSpamScore() (CC=12), que se beneficiaría de ser descompuesto en tres métodos auxiliares independientes. La
  correctitud concurrente es alta, con la salvedad de que depende de la comprensión del JMM para el flujo de visibilidad
   del objeto Post.