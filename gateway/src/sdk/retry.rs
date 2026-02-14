use std::time::Duration;

use reqwest::RequestBuilder;
use reqwest::StatusCode;
use tokio::time::sleep;

use crate::error::GatewayError;

#[derive(Clone, Copy, Debug)]
pub struct RetryPolicy {
    pub max_retries: u32,
    pub base_delay_ms: u64,
}

impl RetryPolicy {
    pub fn new(max_retries: u32, base_delay_ms: u64) -> Self {
        Self {
            max_retries,
            base_delay_ms,
        }
    }
}

pub async fn send_with_retry<F>(
    mut build_request: F,
    retry_policy: RetryPolicy,
) -> Result<reqwest::Response, GatewayError>
where
    F: FnMut() -> RequestBuilder,
{
    let mut attempt = 0;

    loop {
        match build_request().send().await {
            Ok(response) => {
                if should_retry_status(response.status()) && attempt < retry_policy.max_retries {
                    sleep(delay_for_attempt(retry_policy, attempt)).await;
                    attempt += 1;
                    continue;
                }

                return Ok(response);
            }
            Err(error) => {
                if should_retry_error(&error) && attempt < retry_policy.max_retries {
                    sleep(delay_for_attempt(retry_policy, attempt)).await;
                    attempt += 1;
                    continue;
                }

                return Err(GatewayError::Transport(error));
            }
        }
    }
}

fn should_retry_status(status: StatusCode) -> bool {
    matches!(
        status,
        StatusCode::TOO_MANY_REQUESTS
            | StatusCode::INTERNAL_SERVER_ERROR
            | StatusCode::BAD_GATEWAY
            | StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::GATEWAY_TIMEOUT
    )
}

fn should_retry_error(error: &reqwest::Error) -> bool {
    error.is_timeout() || error.is_connect() || error.is_request()
}

fn delay_for_attempt(retry_policy: RetryPolicy, attempt: u32) -> Duration {
    let factor = 1_u64 << attempt.min(5);
    Duration::from_millis(retry_policy.base_delay_ms.saturating_mul(factor))
}
