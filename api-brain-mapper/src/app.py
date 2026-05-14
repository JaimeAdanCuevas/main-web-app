import os
from dotenv import load_dotenv
from flask import Flask, jsonify
from flask_cors import CORS, cross_origin
from flask_migrate import Migrate
from .database.dbConnection import db
from .database.serializers_utils import ma
from .security.bcrypt import bcrypt
from .security.security_headers import setup_security_headers
from .security.error_handler import setup_secure_error_handling
from .security.csrf_protection import csrf
from .routes.errorHandlers import errorHandlers

# load .env file to environment
load_dotenv()

# Import models FIRST to ensure they're registered with SQLAlchemy
from .models.user import User
from .models.role import Role
from .models.model import Model
from .models.inference import Inference
from .models.dataset import Dataset
from .models.model_dataset import ModelDataset
from .models.audit_log import AuditLog
from .models.user_session import UserSession

# Import routers AFTER models
from .routes.auth import auth
from .routes.inferences import inferences
from .routes.datasets import datasets
from .routes.models import models
from .routes.audit import audit
from .routes.users import users
from .routes.admin import admin
from .routes.metrics import metrics

migrate = Migrate()  # Creates an instance of migrate without initialization


def create_app():
    # Create Flask app
    app = Flask(__name__)

    # Configure app depending on environment mode
    if os.getenv("ENV_MODE") == "production":
        from config.production import ProductionConfig

        app.config.from_object(ProductionConfig)
    else:
        from config.development import DevelopmentConfig

        app.config.from_object(DevelopmentConfig)

    # Starts db connection
    db.init_app(app)

    # Close DB session after each request
    @app.teardown_request
    def shutdown_session(exception=None):
        db.session.close()
        db.session.remove()

    # Setup serializer
    ma.init_app(app)

    # Configure migrations
    migrate.init_app(app, db)  # Associates Flask-Migrate to the app

    # Configure flask_bcrypt utility
    bcrypt.init_app(app)

    # Setup security headers
    setup_security_headers(app)

    # Setup secure error handling
    setup_secure_error_handling(app)

    # Initialize CSRF protection
    csrf.init_app(app)

    # Register http error handlers
    app.register_blueprint(errorHandlers)

    # Register routers blueprints
    app.register_blueprint(auth)
    app.register_blueprint(inferences)
    app.register_blueprint(datasets)
    app.register_blueprint(models)
    app.register_blueprint(audit)
    app.register_blueprint(users)
    app.register_blueprint(admin)
    app.register_blueprint(metrics)

    @app.get("/")
    def root_status():
        return (
            jsonify(
                {
                    "service": "NeuroBerry API",
                    "status": "ok",
                    "env": os.getenv("ENV_MODE", "development"),
                    "message": "API is running",
                }
            ),
            200,
        )

    # Setup cors policies
    app.config["CORS_EXPOSE_HEADERS"] = ["Content-Type"]
    app.config["CORS_SUPPORTS_CREDENTIALS"] = True

    # CORS configuration
    if os.getenv("ENV_MODE") == "production":
        # Production origins
        allowed_origins = [
            "https://yourdomain.com",  # Replace with domain
            "https://www.yourdomain.com",
        ]

        production_origin = os.getenv("FRONTEND_URL")
        if production_origin:
            allowed_origins.append(production_origin)

        allow_cloudflare_tunnels = True  # TODO: Add a env to toggle
        if allow_cloudflare_tunnels:
            # Add regex pattern for any cloudflare tunnel subdomain
            allowed_origins.append(r"https://.*\.trycloudflare\.com")
            print("Production mode: Cloudflare tunnels enabled for CORS")

    else:
        # Development origins
        allowed_origins = [
            "http://localhost:5173",  # Vite dev server
            "http://localhost:3000",  # Alternative dev port
            "http://localhost:3003",
            "http://127.0.0.1:5173",
            "http://127.0.0.1:3000",
            "http://127.0.0.1:3003",
            r"https://.*\.trycloudflare\.com",
        ]

        print("Development mode: Allowing all *.trycloudflare.com subdomains for CORS")

    CORS(
        app,
        resources={r"/*": {"origins": allowed_origins}},
        supports_credentials=True,
        expose_headers=["Content-Type"],
    )

    # Initialize dataset and model synchronization on startup
    with app.app_context():
        try:
            from .services.dataset_sync import sync_datasets_with_minio

            sync_datasets_with_minio()
        except Exception as e:
            print(f"Warning: Failed to sync datasets on startup: {e}")

        try:
            from .services.model_sync import sync_models_with_nn_api

            sync_models_with_nn_api()
        except Exception as e:
            print(f"Warning: Failed to sync models on startup: {e}")

    print("Running app")
    return app
