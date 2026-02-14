use std::sync::Arc;

use crate::config::Config;
use crate::providers::registry::ProviderRegistry;

#[derive(Clone)]
pub struct AppState {
    pub registry: Arc<ProviderRegistry>,
    pub config: Arc<Config>,
}

impl AppState {
    pub fn new(registry: Arc<ProviderRegistry>, config: Arc<Config>) -> Self {
        Self { registry, config }
    }
}
