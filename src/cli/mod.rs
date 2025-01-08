//! CLI options and flags.

use std::{env, fs};

use clap::{
    builder::{
        styling::{AnsiColor, Color, Style},
        Styles,
    },
    Parser,
};
use eyre::Context;

mod config;
pub(crate) use config::Config;

#[derive(Debug, Clone, Parser)]
#[command(author, version, styles = cli_styles(), about)]
pub(crate) struct Opts {
    /// The path to the configuration file.
    #[clap(short, long, default_value = "config.toml")]
    pub(crate) config: String,
}

impl Opts {
    /// Parse CLI options into the app [`Config`] struct.
    pub(crate) fn parse_config() -> eyre::Result<Config> {
        dotenvy::dotenv()?;

        let opts = Self::parse();

        let cfg = fs::read_to_string(opts.config).wrap_err("Failed to read config file")?;
        let mut cfg: Config = toml::from_str(&cfg).wrap_err("Failed to parse TOML config file")?;

        // overwrite TOML config with environment variables if set
        // (useful for local development)
        if let Ok(db_url_env) = env::var("DB_URL") {
            cfg.db_url = db_url_env;
        }

        Ok(cfg)
    }
}

/// Styles for the CLI.
const fn cli_styles() -> Styles {
    Styles::styled()
        .usage(Style::new().bold().underline().fg_color(Some(Color::Ansi(AnsiColor::Yellow))))
        .header(Style::new().bold().underline().fg_color(Some(Color::Ansi(AnsiColor::Yellow))))
        .literal(Style::new().fg_color(Some(Color::Ansi(AnsiColor::Green))))
        .invalid(Style::new().bold().fg_color(Some(Color::Ansi(AnsiColor::Red))))
        .error(Style::new().bold().fg_color(Some(Color::Ansi(AnsiColor::Red))))
        .valid(Style::new().bold().underline().fg_color(Some(Color::Ansi(AnsiColor::Green))))
        .placeholder(Style::new().fg_color(Some(Color::Ansi(AnsiColor::White))))
}

#[cfg(test)]
mod tests {
    use super::Opts;

    #[test]
    fn test_verify_cli() {
        use clap::CommandFactory;
        Opts::command().debug_assert()
    }
}
