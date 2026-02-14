use std::env;

#[derive(Clone, Debug)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub openai_base_url: String,
    pub anthropic_base_url: String,
    pub gemini_base_url: String,
    pub kimi_base_url: String,
    pub gateway_api_keys: Vec<String>,
    pub openai_api_key: Option<String>,
    pub anthropic_api_key: Option<String>,
    pub gemini_api_key: Option<String>,
    pub kimi_api_key: Option<String>,
    pub upstream_max_retries: u32,
    pub upstream_retry_base_delay_ms: u64,
    pub request_timeout_secs: u64,
}

impl Config {
    pub fn from_env() -> Self {
        let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
        let port = env::var("PORT")
            .ok()
            .and_then(|value| value.parse::<u16>().ok())
            .unwrap_or(3000);

        let openai_base_url = env::var("OPENAI_BASE_URL")
            .unwrap_or_else(|_| "https://api.openai.com".to_string())
            .trim_end_matches('/')
            .to_string();

        let anthropic_base_url = env::var("ANTHROPIC_BASE_URL")
            .unwrap_or_else(|_| "https://api.anthropic.com".to_string())
            .trim_end_matches('/')
            .to_string();

        let gemini_base_url = env::var("GEMINI_BASE_URL")
            .unwrap_or_else(|_| {
                "https://generativelanguage.googleapis.com/v1beta/openai".to_string()
            })
            .trim_end_matches('/')
            .to_string();

        let kimi_base_url = env::var("KIMI_BASE_URL")
            .unwrap_or_else(|_| "https://api.kimi.com/coding/v1".to_string())
            .trim_end_matches('/')
            .to_string();

        let request_timeout_secs = env::var("REQUEST_TIMEOUT_SECS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(120);

        let gateway_api_keys = env::var("GATEWAY_API_KEYS")
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
            .collect::<Vec<_>>();

        let openai_api_key = env::var("OPENAI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let anthropic_api_key = env::var("ANTHROPIC_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let gemini_api_key = env::var("GEMINI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let kimi_api_key = env::var("KIMI_API_KEY")
            .ok()
            .map(|value| value.trim().to_string())
            .filter(|value| !value.is_empty());

        let upstream_max_retries = env::var("UPSTREAM_MAX_RETRIES")
            .ok()
            .and_then(|value| value.parse::<u32>().ok())
            .unwrap_or(2);

        let upstream_retry_base_delay_ms = env::var("UPSTREAM_RETRY_BASE_DELAY_MS")
            .ok()
            .and_then(|value| value.parse::<u64>().ok())
            .unwrap_or(150);

        Self {
            host,
            port,
            openai_base_url,
            anthropic_base_url,
            gemini_base_url,
            kimi_base_url,
            gateway_api_keys,
            openai_api_key,
            anthropic_api_key,
            gemini_api_key,
            kimi_api_key,
            upstream_max_retries,
            upstream_retry_base_delay_ms,
            request_timeout_secs,
        }
    }

    pub fn bind_addr(&self) -> String {
        format!("{}:{}", self.host, self.port)
    }
}
