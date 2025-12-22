use crate::config::CONFIG;

use lettre::{
        message::Message,
        SmtpTransport, Transport,
        transport::smtp::authentication::Credentials,
        message::{header::ContentType}
};

pub async fn send_email(
    to: &str,
    subject: &str,
    html_body: &str
) -> anyhow::Result<()> {
    let email = Message::builder()
        .from(CONFIG.smtp2go_from.parse()?)
        .to(to.parse()?)
        .subject(subject)
        .header(ContentType::TEXT_HTML)
        .body(html_body.to_string())?;

    let creds = Credentials::new(
        CONFIG.smtp2go_login.clone(),
        CONFIG.smtp2go_password.clone()
    );

    let mailer = SmtpTransport::relay("mail.smtp2go.com")?
        .credentials(creds)
        .build();

    mailer.send(&email)?;
    
    Ok(())
}
