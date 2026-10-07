use crate::config::MenuEntry;
use crate::error::Result;
use handlebars::Handlebars;
use serde_json::json;

pub struct GrubMenuBuilder<'a> {
    entries: Vec<MenuEntry>,
    default_entry: Option<usize>,
    timeout: Option<u32>,
    handlebars: Handlebars<'a>,
}

impl<'a> GrubMenuBuilder<'a> {
    /// Returns `Err` instead of panicking if `MENUENTRY_TEMPLATE` fails to
    /// register -- this can in practice only happen from a programming
    /// error in that constant (it's not runtime/user input), but a
    /// template-registration failure propagating as a normal error still
    /// beats taking down the whole `pxe-boot-prepare` process over a
    /// template bug that one broken ISO/interface could have been
    /// isolated from (see lib.rs's per-ISO/per-interface failure
    /// isolation, which a panic here would bypass entirely).
    pub fn new() -> Result<Self> {
        let mut handlebars = Handlebars::new();

        handlebars
            .register_template_string("menuentry", MENUENTRY_TEMPLATE)
            .map_err(|e| {
                crate::error::PxeBootError::Config(format!(
                    "Failed to register GRUB menuentry template: {e}"
                ))
            })?;

        Ok(Self {
            entries: Vec::new(),
            default_entry: None,
            timeout: None,
            handlebars,
        })
    }

    pub fn add_entry(&mut self, entry: MenuEntry) -> &mut Self {
        self.entries.push(entry);
        self
    }

    pub fn add_placeholder_entry(&mut self, file_name: &str, reason: &str) -> &mut Self {
        self.placeholders
            .push((file_name.to_string(), reason.to_string()));
        self
    }

    pub fn set_default(&mut self, index: usize) -> &mut Self {
        self.default_entry = Some(index);
        self.timeout = Some(5); // Auto-enable timeout
        self
    }

    pub fn set_timeout(&mut self, seconds: u32) -> &mut Self {
        self.timeout = Some(seconds);
        self
    }

    pub fn build(&self) -> Result<String> {
        let mut output = String::new();

        // Initialize network for HTTP device support
        // Load required modules
        output.push_str("insmod http\n");
        output.push_str("insmod net\n");
        output.push_str("insmod efinet\n");
        output.push_str("\n");
        
        // Try to initialize network using DHCP/BOOTP
        // Use GRUB's if statement to ignore errors
        output.push_str("# Initialize network for HTTP access\n");
        output.push_str("if net_bootp; then\n");
        output.push_str("  echo Network initialized via BOOTP\n");
        output.push_str("else\n");
        output.push_str("  echo Network already configured or BOOTP failed\n");
        output.push_str("fi\n");
        output.push_str("\n");

        // Header
        output.push_str("if [ x$feature_timeout_style = xy ] ; then\n");
        if let Some(timeout) = self.timeout {
            output.push_str("  set timeout_style=menu\n");
            output.push_str(&format!("  set timeout={}\n", timeout));
        } else {
            output.push_str("  # set timeout_style=menu\n");
            output.push_str("  # set timeout=5\n");
        }
        output.push_str("else\n");
        if let Some(timeout) = self.timeout {
            output.push_str(&format!("  set timeout={}\n", timeout));
        } else {
            output.push_str("  # set timeout=5\n");
        }
        output.push_str("fi\n\n");

        // Default entry
        if let Some(default) = self.default_entry {
            output.push_str(&format!("set default={}\n\n", default));
        } else {
            output.push_str("# set default=\n\n");
        }

        // Menu entries
        for entry in &self.entries {
            output.push_str(&self.render_entry(entry)?);
            output.push('\n');
        }

        // Reload entry for convenience
        output.push_str("menuentry \"Reload Grub\" {\n");
        output.push_str("    configfile /grub/grub.cfg\n");
        output.push_str("}\n");

        Ok(output)
    }

    fn render_entry(&self, entry: &MenuEntry) -> Result<String> {
        let data = json!({
            "title": escape_grub_string(&entry.title),
            "kernel_url": entry.kernel_url,
            "kernel_params": entry.kernel_params.join(" "),
            "initrd_url": entry.initrd_url,
        });

        Ok(self.handlebars.render("menuentry", &data)?)
    }
}

/// Escapes a string for safe use inside a GRUB double-quoted string
/// (GRUB's own config-file lexer, not HTML). GRUB requires backslash and
/// double-quote to be backslash-escaped within `"..."`; anything else
/// (including `&`) is a literal character to GRUB, unlike HTML. Must run
/// BEFORE Handlebars rendering, with the template field left as a raw
/// (triple-brace) substitution -- Handlebars' default double-brace
/// HTML-escaping would otherwise mangle this escaping itself (e.g.
/// turning our already-correct `\"` into `\&quot;`).
fn escape_grub_string(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        // GRUB's config parser is line-oriented: a literal newline (or
        // carriage return) inside what's supposed to be a one-line
        // `menuentry "..." {` declaration terminates that line early
        // regardless of quote balance, letting whatever follows be
        // interpreted as a new top-level GRUB command. Backslash-escaping
        // doesn't protect against this -- GRUB has no `\n` escape
        // sequence inside a double-quoted string -- so these must be
        // neutralized outright rather than escaped.
        .replace(['\n', '\r'], " ")
}

const MENUENTRY_TEMPLATE: &str = r#"menuentry "{{title}}" {
    set gfxpayload=keep
    linux  {{{kernel_url}}} {{{kernel_params}}}
    initrd {{{initrd_url}}}
}"#;

#[cfg(test)]
mod tests {
    use super::*;

    fn entry_with_title(title: &str) -> MenuEntry {
        MenuEntry {
            title: title.to_string(),
            kernel_url: "http://gw:80/vmlinuz".to_string(),
            kernel_params: vec!["foo=bar".to_string()],
            initrd_url: "http://gw:80/initrd".to_string(),
            position: 0,
            architecture: None,
        }
    }

    #[test]
    fn escapes_quotes_and_backslashes_without_html_entities() {
        let builder = GrubMenuBuilder::new().unwrap();
        let entry = entry_with_title(r#"My "Weird" \Title & Co"#);

        let rendered = builder.render_entry(&entry).unwrap();

        // GRUB-correct escaping: quotes/backslashes backslash-escaped.
        assert!(rendered.contains(r#"My \"Weird\" \\Title & Co"#));
        // Must NOT be HTML-entity-escaped (that's meaningless to GRUB and
        // would literally show "&amp;" etc. in the boot menu).
        assert!(!rendered.contains("&quot;"));
        assert!(!rendered.contains("&amp;"));
    }

    #[test]
    fn strips_newlines_from_title_to_prevent_grub_script_injection() {
        // GRUB's config parser is line-oriented: an embedded literal
        // newline inside what's supposed to be a one-line
        // `menuentry "..." {` declaration terminates that line early
        // regardless of quote balance -- backslash-escaping alone
        // (GRUB has no `\n` string escape) doesn't protect against a
        // filename/script-name containing one.
        let builder = GrubMenuBuilder::new().unwrap();
        let entry = entry_with_title("evil\"\nmenuentry \"injected");

        let rendered = builder.render_entry(&entry).unwrap();

        // MENUENTRY_TEMPLATE is itself multi-line (formatting: the
        // menuentry/set/linux/initrd/`}` lines) -- that's expected and
        // fine. What matters is the title's OWN embedded newline must
        // not ADD an extra line: the escaped title (with its embedded
        // newline neutralized to a space) must stay confined to the
        // opening `menuentry "..." {` line, not spill the attacker's
        // "menuentry \"injected" text onto its own line.
        assert_eq!(rendered.lines().count(), 5, "rendered:\n{rendered}");
        let first_line = rendered.lines().next().unwrap();
        let expected_title = escape_grub_string("evil\"\nmenuentry \"injected");
        assert_eq!(first_line, format!("menuentry \"{expected_title}\" {{"));
        assert!(!expected_title.contains('\n'));
    }


    #[test]
    fn renders_plain_title_unchanged() {
        let builder = GrubMenuBuilder::new().unwrap();
        let entry = entry_with_title("Plain Title");

        let rendered = builder.render_entry(&entry).unwrap();

        assert!(rendered.contains(r#"menuentry "Plain Title" {"#));
    }

    #[test]
    fn entry_with_unknown_architecture_is_not_wrapped_in_a_grub_cpu_conditional() {
        let builder = GrubMenuBuilder::new().unwrap();
        let entry = entry_with_title("No Arch");

        let rendered = builder.render_entry(&entry).unwrap();

        assert!(!rendered.contains("$grub_cpu"), "rendered:\n{rendered}");
    }

    #[test]
    fn entry_with_x86_64_architecture_is_wrapped_in_a_grub_cpu_conditional() {
        let builder = GrubMenuBuilder::new().unwrap();
        let mut entry = entry_with_title("x86_64 Entry");
        entry.architecture = Some("x86_64".to_string());

        let rendered = builder.render_entry(&entry).unwrap();

        assert!(
            rendered.contains("if [ \"$grub_cpu\" = \"x86_64\" ]; then"),
            "rendered:\n{rendered}"
        );
        assert!(rendered.trim_end().ends_with("fi"), "rendered:\n{rendered}");
        assert!(rendered.contains(r#"menuentry "x86_64 Entry" {"#));
    }

    #[test]
    fn entry_with_aarch64_architecture_is_wrapped_using_grubs_arm64_not_aarch64() {
        // A6's whole reason for existing: GRUB's OWN $grub_cpu value for
        // an aarch64 build is "arm64", not "aarch64" -- confirmed against
        // GRUB's configure.ac (see distro::arch::to_grub_cpu). Getting
        // this wrong would hide every aarch64 ISO from aarch64 clients
        // themselves.
        let builder = GrubMenuBuilder::new().unwrap();
        let mut entry = entry_with_title("aarch64 Entry");
        entry.architecture = Some("aarch64".to_string());

        let rendered = builder.render_entry(&entry).unwrap();

        assert!(
            rendered.contains("if [ \"$grub_cpu\" = \"arm64\" ]; then"),
            "rendered:\n{rendered}"
        );
        assert!(!rendered.contains("\"aarch64\""), "rendered:\n{rendered}");
    }

    #[test]
    fn entry_with_unmappable_architecture_fails_open_and_is_not_wrapped() {
        let builder = GrubMenuBuilder::new().unwrap();
        let mut entry = entry_with_title("PowerPC Entry");
        entry.architecture = Some("ppc64le".to_string());

        let rendered = builder.render_entry(&entry).unwrap();

        assert!(!rendered.contains("$grub_cpu"), "rendered:\n{rendered}");
        assert!(rendered.contains(r#"menuentry "PowerPC Entry" {"#));
    }

    #[test]
    fn build_with_no_entries_still_includes_header_and_reload_entry() {
        let builder = GrubMenuBuilder::new().unwrap();
        let cfg = builder.build().unwrap();

        assert!(cfg.contains("insmod http"));
        assert!(cfg.contains("insmod net"));
        assert!(cfg.contains("net_bootp"));
        // No default configured -- must be the commented-out placeholder,
        // not a real `set default=` line.
        assert!(cfg.contains("# set default=\n"));
        assert!(!cfg.contains("\nset default="));
        assert!(cfg.contains(r#"menuentry "Reload Grub" {"#));
        assert!(cfg.contains("configfile /grub/grub.cfg"));
    }

    #[test]
    fn placeholder_entry_shows_filename_and_reason_and_is_not_bootable() {
        let reason = "Unknown distribution type";
        let rendered = render_placeholder("mystery.iso", reason);

        assert!(rendered.contains(r#"menuentry "mystery.iso (unsupported)""#));
        assert!(rendered.contains(reason));
        // Must NOT contain `linux`/`initrd` boot commands -- it's a
        // dead-end informational entry, not something that attempts to
        // boot.
        assert!(!rendered.contains("linux "));
        assert!(!rendered.contains("initrd "));
        assert!(rendered.contains("configfile /grub/grub.cfg"));
    }

    #[test]
    fn placeholder_entry_escapes_quotes_and_newlines_in_reason() {
        // `reason` is error text, not operator-authored -- could contain
        // a file path with an embedded `"`, or (less plausibly but not
        // impossible) a newline from a nested error's Display impl. Same
        // injection class A1 already fixed for real entry titles --
        // applies to BOTH the title (filename) and the echoed reason
        // line here.
        let rendered = render_placeholder(
            "evil\".iso",
            "boot.json did not parse: unexpected \"quote\"\nand a newline",
        );

        assert_eq!(rendered.matches("menuentry \"").count(), 1);
        let first_line = rendered.lines().next().unwrap();
        assert!(first_line.starts_with("menuentry \"evil\\\".iso (unsupported)\" {"));
        // The reason's embedded newline must not have produced an extra
        // line -- the whole echoed reason stays on ONE line (neutralized
        // to a space), same as the title.
        assert!(rendered.contains("unexpected \\\"quote\\\" and a newline"));
    }

    #[test]
    fn build_renders_placeholder_entries_after_real_entries_before_reload() {
        let mut builder = GrubMenuBuilder::new().unwrap();
        builder.add_entry(entry_with_title("Real Entry"));
        builder.add_placeholder_entry("broken.iso", "Unknown distribution type");

        let cfg = builder.build().unwrap();

        let real_pos = cfg.find(r#"menuentry "Real Entry""#).unwrap();
        let placeholder_pos = cfg.find(r#"menuentry "broken.iso (unsupported)""#).unwrap();
        let reload_pos = cfg.find(r#"menuentry "Reload Grub""#).unwrap();

        assert!(real_pos < placeholder_pos, "real entry should render first");
        assert!(
            placeholder_pos < reload_pos,
            "placeholder should render before Reload Grub"
        );
    }

    #[test]
    fn build_renders_all_entries_in_position_order_before_reload_entry() {
        let mut builder = GrubMenuBuilder::new().unwrap();
        builder.add_entry(entry_with_title("First"));
        builder.add_entry(entry_with_title("Second"));

        let cfg = builder.build().unwrap();

        let first_pos = cfg.find(r#"menuentry "First""#).unwrap();
        let second_pos = cfg.find(r#"menuentry "Second""#).unwrap();
        let reload_pos = cfg.find(r#"menuentry "Reload Grub""#).unwrap();
        assert!(first_pos < second_pos);
        assert!(second_pos < reload_pos);
    }

    #[test]
    fn set_default_also_auto_enables_a_five_second_timeout() {
        let mut builder = GrubMenuBuilder::new().unwrap();
        builder.add_entry(entry_with_title("Only"));
        builder.set_default(0);

        let cfg = builder.build().unwrap();

        assert!(cfg.contains("set default=0"));
        assert!(cfg.contains("set timeout=5"));
    }

    #[test]
    fn set_timeout_without_default_sets_timeout_but_leaves_default_commented() {
        let mut builder = GrubMenuBuilder::new().unwrap();
        builder.set_timeout(10);

        let cfg = builder.build().unwrap();

        assert!(cfg.contains("set timeout=10"));
        assert!(cfg.contains("# set default=\n"));
    }
}
