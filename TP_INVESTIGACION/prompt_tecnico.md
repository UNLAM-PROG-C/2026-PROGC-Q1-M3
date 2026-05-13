Lenguaje de programación

 Java 17 (LTS) o superior. Compilar y ejecutar como proyecto Maven.

 Plataforma

 El programa debe ejecutarse en Windows. Build con mvn package desde la carpeta raíz; ejecución con java -jar target/tp-concurrente-1.0-SNAPSHOT.jar (o mvn
  exec:java -Dexec.mainClass=com.tp.Main). Requisitos: JDK 17+ y Maven 3.8+ instalados en el sistema.

 Funciones a implementar

 Desarrollar un programa local que simule un servidor de análisis de posts de Twitter. El programa lee posts desde src/main/resources/posts.json, los
 procesa concurrentemente a través de un pipeline de tres etapas, y guarda los resultados en resultados.json en la raíz del proyecto.

 Estructura del pipeline (obligatoria):

 Productor (1 thread) -> [BlockingQueue_in]
                               |
                               v
                        Pool A — Sentimiento   (K_A threads)
                               |
                               v
                          [BlockingQueue_AB]
                               |
                               v
                        Pool B — Categorías    (K_B threads)
                               |
                               v
                          [BlockingQueue_BC]
                               |
                               v
                        Pool C — Spam + Decisión (K_C threads)
                               |
                               v
                 ConcurrentLinkedQueue<Resultado>
                               |
                               v
                        Dump a resultados.json

 Cada etapa es un ExecutorService independiente creado con Executors.newFixedThreadPool(K_X). La comunicación entre etapas se hace exclusivamente a través
 de BlockingQueue<T> (LinkedBlockingQueue con capacidad limitada — por ejemplo 50 — para mostrar backpressure). NO se permite compartir colecciones
 mutables entre etapas — solo BlockingQueue thread-safe.

 Etapa 0 — Productor (1 thread dedicado, ejecutado con new Thread() o un ExecutorService de un solo thread):

 - Lee posts.json desde el classpath usando getResourceAsStream. El JSON contiene un array de objetos {"post_id": int, "texto": String}.
 - Inyecta cada post en BlockingQueue_in (usar .put() para bloquear ante backpressure).
 - Al terminar, inyecta K_A "poison pills" — usar un objeto centinela tipado, por ejemplo Post POISON_PILL = new Post(-1, null); o mejor un sealed
 interface PipelineMessage permits PostMessage, PoisonPill {}.

 Etapa A — Análisis de sentimiento (Pool A):

 - Cada worker submitea a ExecutorService_A un loop que consume de BlockingQueue_in.
 - Implementación con léxico manual: dos listas en palabras_sentimiento.json con estructura:
 {
   "positivas": ["bueno", "excelente", "genial", "feliz", "amor", ...],
   "negativas": ["malo", "terrible", "horrible", "triste", "odio", ...]
 }
 - Cargar las listas UNA SOLA VEZ al iniciar la etapa (estático o inyectado), no por mensaje.
 - Algoritmo: tokenizar texto (lowercase + split por whitespace/puntuación), contar matches en cada lista.
   - hits_pos > hits_neg → "positivo"
   - hits_pos < hits_neg → "negativo"
   - empate (incluyendo 0-0) → "neutro"
 - Agrega sentimiento al objeto y lo pasa a BlockingQueue_AB.
 - Al recibir una poison pill, propaga UNA pill a la siguiente cola y termina ese worker. Cuando todas las pills hayan circulado, la etapa siguiente
 recibirá K_A pills (lo que es suficiente para parar K_B workers si K_A >= K_B; si no, propagar max(K_A, K_B) desde el inicio o tener una etapa de fan-out
 de pills).
   - Recomendación más simple: propagar exactamente K_siguiente poison pills al detectar la primera pill en la etapa actual (con un AtomicBoolean que
 asegure que solo un worker propaga). Esto desacopla los tamaños de pool.

 Etapa B — Clasificación de contenido prohibido (Pool B):

 - Cada worker consume de BlockingQueue_AB.
 - Compara el texto (tokenizado lowercase) contra palabras_prohibidas.json, con estructura:
 {
   "violencia": ["matar", "golpear", "atacar", ...],
   "odio":      ["estupido", "idiota", "asqueroso", ...],
   "adulto":    ["sexo", "porno", "nsfw", ...]
 }
 - Devuelve una List<String> con las categorías detectadas (vacía si limpio).
 - Agrega categorias al objeto y pasa a BlockingQueue_BC.
 - Maneja poison pills como en la etapa A.

 Etapa C — Spam, decisión final y persistencia (Pool C):

 - Cada worker consume de BlockingQueue_BC.
 - Calcula spamScore en [0.0, 1.0] combinando tres heurísticas con pesos fijos:
   - Keywords spam (peso 0.4): Pattern.compile("(?i)(gratis|comprar ya|click aqui|\\$\\$+|!!!|https?://)"). Por cada match aportar proporcionalmente; al
 menos 1 match suma todo el peso.
   - Ratio mayúsculas (peso 0.3): si letrasMayúsculas / totalLetras > 0.7, suma todo el peso.
   - Longitud anómala (peso 0.3): si texto.length() < 5 o > 280, suma todo el peso.
   - Resultado clampeado a [0.0, 1.0].
 - Decisión ("APROBADO" o "RECHAZADO"):
   - RECHAZADO si: !categorias.isEmpty(), o spamScore > 0.7, o (sentimiento.equals("negativo") && categorias.contains("odio")).
   - Caso contrario: APROBADO.
 - Mide tiempoProcesamientoMs por post: tiempo desde que el productor lo inyectó en BlockingQueue_in hasta que la etapa C termina con él. Usar
 System.nanoTime() y guardar el timestamp de entrada en el propio objeto del post.
 - Construye el Resultado con el formato JSON especificado más abajo.
 - Agrega el Resultado a una ConcurrentLinkedQueue<Resultado> compartida (lock-free, evita el cuello de botella de un Lock o synchronized).

 Al finalizar el pipeline (todos los pools cerraron via executor.shutdown() + awaitTermination()):

 - Volcar la cola de resultados a resultados.json con Gson + setPrettyPrinting().
 - Imprimir métricas a System.out:
   - Tiempo total del pipeline (productor inicia → último resultado guardado).
   - Throughput (posts / segundo).
   - Tiempo promedio por post (promedio de tiempoProcesamientoMs).
   - Tiempo promedio por etapa (cada etapa acumula su tiempo en un LongAdder o AtomicLong).

 Requisitos específicos

 - Concurrencia: tres ExecutorService distintos vía Executors.newFixedThreadPool(n), uno por etapa. Tamaños configurables como constantes al inicio de
 Main.java (por defecto: K_A = 3, K_B = 3, K_C = 3).
 - Sincronización:
   - Solo BlockingQueue entre etapas (LinkedBlockingQueue con capacidad).
   - ConcurrentLinkedQueue para resultados finales (lock-free).
   - AtomicLong o LongAdder para contadores compartidos (tiempo por etapa, contador de procesados).
   - NO usar synchronized ni ReentrantLock salvo justificación explícita.
 - Shutdown ordenado: usar poison pills propagadas entre etapas. Cada etapa, al detectar la primera pill, propaga K_siguiente pills a la cola siguiente
 (proteger con AtomicBoolean para que solo un worker propague). Llamar shutdown() en cada ExecutorService y awaitTermination() antes de pasar a la
 siguiente.
 - Logging: usar java.util.logging.Logger con format que incluya nombre del thread. Configurar al inicio:
 System.setProperty("java.util.logging.SimpleFormatter.format",
     "[%1$tT.%1$tL] [%4$s] [%2$s] %5$s%n");
 - Cada etapa loguea (INFO) cuando recibe un post y cuando lo termina, incluyendo Thread.currentThread().getName().
 - Formato de cada Resultado en resultados.json (obligatorio, exacto — usar @SerializedName si los campos en Java siguen camelCase pero el JSON debe ser
 snake_case):
 {
   "post_id": 42,
   "texto": "...",
   "spam_score": 0.87,
   "sentimiento": "negativo",
   "categorias": ["odio"],
   "decision": "RECHAZADO",
   "tiempo_procesamiento_ms": 34
 }
 - Dataset de entrada posts.json (~100 posts en ESPAÑOL, generados por la IA, variados):
   - Mezcla balanceada de sentimientos.
   - ~15 con palabras prohibidas (al menos uno por categoría).
   - ~10 claramente spam (mayúsculas excesivas, links, "GRATIS!!!", $$$, repeticiones).
   - ~5 con longitud anómala (muy cortos o muy largos).
   - El resto, posts limpios y normales.
 - Diccionarios palabras_prohibidas.json y palabras_sentimiento.json con al menos 8-10 palabras por categoría/sentimiento. Ubicados en src/main/resources/.
 - pom.xml con:
   - <maven.compiler.source>17</maven.compiler.source>
   - <maven.compiler.target>17</maven.compiler.target>
   - Dependencia única: com.google.code.gson:gson:2.10.1
   - maven-shade-plugin para generar un jar ejecutable (fat jar) con Main-Class configurado.

 Estructura de archivos sugerida:

 .
 ├── pom.xml
 ├── src/main/java/com/tp/
 │   ├── Main.java                  # orquesta pipeline, métricas, dump JSON
 │   ├── Productor.java             # lee posts.json, inyecta en BlockingQueue_in
 │   ├── analisis/
 │   │   ├── EtapaSentimiento.java  # Pool A
 │   │   ├── EtapaCategorias.java   # Pool B
 │   │   └── EtapaSpam.java         # Pool C (spam + decisión)
 │   └── modelo/
 │       ├── Post.java              # post en tránsito por el pipeline
 │       ├── Resultado.java         # objeto final con @SerializedName
 │       └── PoisonPill.java        # centinela (o sealed interface)
 ├── src/main/resources/
 │   ├── posts.json
 │   ├── palabras_prohibidas.json
 │   └── palabras_sentimiento.json
 └── resultados.json                # generado al correr

 Restricciones

 - Programa simple, a fines demostrativos. Sin frameworks (Spring, Quarkus, etc.), sin GUI, sin base de datos, sin servidor HTTP.
 - Única dependencia externa permitida: Gson (com.google.code.gson:gson). Todo lo demás de la stdlib de Java (java.util.concurrent, java.util.regex,
 java.util.logging).
 - Sin virtual threads (Project Loom). Usar platform threads clásicos con Executors.newFixedThreadPool(n).
 - Sin CompletableFuture ni reactive streams. El patrón es pipeline tradicional con BlockingQueue y workers en ExecutorService.
 - Posts en español.
 - Comentarios SOLO donde la concurrencia no sea obvia (por qué ConcurrentLinkedQueue en lugar de synchronized List, por qué poison pills, por qué
 BlockingQueue con capacidad limitada). NO comentar lo evidente.