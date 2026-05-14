# NeuroBerry — Wiki de operación

## Inicio rápido (un comando)

```bash
cd main-web-app
chmod +x start.sh stop.sh healthcheck.sh
./start.sh
```

Eso es todo. El script crea todos los archivos de configuración, genera secretos, levanta los servicios y verifica que todo esté funcionando.

La primera vez tarda más porque Docker descarga e instala dependencias. Las siguientes veces es rápido.

Opciones del script de inicio:

```bash
./start.sh --rebuild
./start.sh --mode full
./start.sh --mode lite --nn-host http://192.168.1.50:8080
```

- `--mode full`: levanta también `neural-network-api` localmente.
- `--mode lite`: no levanta inferencia local; usa un host externo para `NN_API_HOST`.

---

## URLs de acceso

| Servicio | URL | Descripción |
|---|---|---|
| Aplicación Web | http://localhost:3003 | Frontend Vue.js |
| API Principal | http://localhost:5000 | REST API Flask |
| MinIO Consola | http://localhost:9001 | Gestión de archivos |
| API Inferencia | http://localhost:8080/health | FastAPI YOLO |
| Base de Datos | localhost:5432 | Solo clientes SQL, no navegador |

---

## Credenciales por defecto

| Acceso | Usuario / Email | Contraseña |
|---|---|---|
| Aplicación Web | admin@gmail.com | Pass$612345 |
| MinIO Consola | minioadmin | minioadmin123 |
| PostgreSQL | neuroberry_user | password_seguro_123 |
| PostgreSQL admin | postgres | postgres_dev_pass |

> **Importante:** Cambia las contraseñas antes de exponer el sistema en una red pública.

---

## Estructura del proyecto

```
/
├── main-web-app/               ← Stack principal
│   ├── start.sh                ← Inicio con un clic
│   ├── stop.sh                 ← Parada limpia
│   ├── healthcheck.sh          ← Verificación de salud
│   ├── docker-compose.dev.yml  ← Orquestación
│   ├── .env                    ← Variables generales (auto-creado)
│   ├── api-brain-mapper/       ← API Flask
│   │   └── .env                ← Variables de API (auto-creado)
│   ├── webclient/              ← Frontend Vue.js
│   │   └── .env                ← URL de la API (auto-creado)
│   └── datasets/               ← Datasets locales para subir a MinIO
│
└── neural-network-api/         ← API de inferencia YOLO
    ├── docker-composer.dev.yaml
    ├── .env                    ← Variables (auto-creado)
    └── models/
        └── weights/
            └── best.pt         ← ← Coloca aquí tu modelo YOLO
```

---

## Agregar un modelo YOLO

1. Copia tu archivo `best.pt` a `neural-network-api/models/weights/best.pt`
2. Reinicia la API de inferencia:

```bash
cd neural-network-api
docker compose -f docker-composer.dev.yaml restart neural-api
```

3. Verifica que cargó:

```bash
docker compose -f docker-composer.dev.yaml logs --tail=20 neural-api | grep -E "model|Model|AI"
```

Debes ver: `AI model loaded and warmed up successfully.`

---

## Comandos útiles

### Verificar que todo funciona
```bash
cd main-web-app
./healthcheck.sh
```

### Ver logs en tiempo real
```bash
# Todos los servicios
cd main-web-app && docker compose -f docker-compose.dev.yml logs -f

# Solo la API Flask
docker logs -f flask_app

# Solo la inferencia
docker logs -f neural-api-dev
```

### Reiniciar un servicio específico
```bash
cd main-web-app
docker compose -f docker-compose.dev.yml restart flask_api
docker compose -f docker-compose.dev.yml restart webclient
docker compose -f docker-compose.dev.yml restart s3
```

### Acceder a la base de datos por terminal
```bash
docker exec -it main-web-app-postgres-1 psql -U neuroberry_user -d neurobberry_db
```

### Ver estado de todos los contenedores
```bash
cd main-web-app && docker compose -f docker-compose.dev.yml ps
cd neural-network-api && docker compose -f docker-composer.dev.yaml ps
```

---

## Parar el sistema

### Parada normal (conserva datos)
```bash
cd main-web-app
./stop.sh
```

### Parada eliminando imágenes (fuerza rebuild en próximo inicio)
```bash
./stop.sh --clean
```

### Reset completo (⚠️ borra base de datos y archivos de MinIO)
```bash
./stop.sh --volumes
```

---

## Inicio con rebuild de imágenes

Úsalo cuando hagas cambios en los Dockerfiles o requirements.txt:

```bash
cd main-web-app
./start.sh --rebuild
```

---

## Modo Raspberry

Si quieres usar Raspberry con menos carga, usa `lite` y deja la inferencia en otra máquina.

### Perfil recomendado en Raspberry (lite)

```bash
cd main-web-app
./start.sh --mode lite --nn-host http://IP_DEL_SERVIDOR_IA:8080
```

Esto levanta en Raspberry:
- webclient
- flask_api
- postgres
- s3/minio

Y usa la inferencia remota en `NN_API_HOST`.

### Perfil completo en Raspberry (full)

```bash
cd main-web-app
./start.sh --mode full --rebuild
```

Usa este perfil solo si tu Raspberry tiene recursos suficientes (ideal Pi 5 / 8GB).

---

## Con proxy corporativo

Si tu máquina usa proxy (ej. red Intel), expórtalo antes de ejecutar `start.sh`:

```bash
export http_proxy="http://proxy-intel.proxy.com:822"
export https_proxy="http://proxy-intel.proxy.com:822"
./start.sh
```

Sin proxy (red normal, casa, servidor externo): ejecuta `./start.sh` directamente sin exportar nada.

---

## Solución de problemas frecuentes

### La API Flask no arranca
```bash
docker logs flask_app | tail -40
```
Causa más común: la base de datos aún no está lista. Espera 10 segundos y el contenedor se recupera solo.

### MinIO devuelve "InvalidAccessKeyId"
El usuario S3 de la app no fue creado. Solución:
```bash
cd main-web-app && ./start.sh
```
El script detecta que MinIO ya corre y solo hace el bootstrap del usuario.

### La API de inferencia dice "Model not found"
El archivo `best.pt` no está en la ruta correcta. Verifica:
```bash
ls -lah neural-network-api/models/weights/
```
Si no está: copia tu `best.pt` ahí y reinicia `neural-api`.

### Puerto ocupado
Algún otro proceso usa el puerto 3003, 5000, 8080, 9000 o 9001:
```bash
ss -tlnp | grep -E '3003|5000|8080|9000|9001'
```
Detén el proceso conflictivo o cambia el puerto en `docker-compose.dev.yml`.

### Reset total del entorno
```bash
cd main-web-app
./stop.sh --clean --volumes
./start.sh
```

---

## Arquitectura de servicios

```
Navegador
   │
   ├── :3003  webclient (Vue.js + Vite)
   │             │
   └── :5000  flask_api (Flask)
                 │
                 ├── :5432  postgres (PostgreSQL)
                 ├── :9000  s3 (MinIO - API)
                 └── :8080  neural-api (FastAPI + YOLO)

:9001  MinIO Consola (acceso directo, no pasa por Flask)
```
