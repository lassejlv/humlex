use axum::{
    routing::get,
    Json,
    Router,
};
use serde::Serialize;
use std::env;

#[derive(Serialize)]
struct StatusResponse {
    status: String,
}

async fn root() -> &'static str {
    "Hello, World!"
}

async fn status() -> Json<StatusResponse> {
    Json(StatusResponse {
        status: "ok".to_string(),
    })
}

#[tokio::main]
async fn main() {
    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port = env::var("PORT").unwrap_or_else(|_| "3000".to_string());
    let addr = format!("{}:{}", host, port);

    let app = Router::new()
        .route("/", get(root))
        .route("/status", get(status));

    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
