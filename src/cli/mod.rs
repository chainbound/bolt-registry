//! CLI options parsing and configuration loading.

use clap::{
    builder::{
        styling::{AnsiColor, Color, Style},
        Styles,
    },
    Parser,
};
use figment::{
    providers::{Env, Format, Toml},
    Figment,
};

/// The program configuration structs.
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
    /// Parse CLI options into the app [`Config`] struct and return it.
    ///
    /// This function will load the configuration from the TOML file and
    /// override it with environment variables when they exist.
    pub(crate) fn parse_config() -> eyre::Result<Config> {
        dotenvy::dotenv()?;

        let opts = Self::parse();

        // 1. Load the configuration from the TOML file.
        // 2. Merge the configuration with the environment variables.
        // 3. Extract the configuration into the `Config` struct.
        let cfg = Figment::new().merge(Toml::file(opts.config)).merge(Env::raw()).extract()?;

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
