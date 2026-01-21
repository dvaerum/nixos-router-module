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
    pub fn new() -> Self {
        let mut handlebars = Handlebars::new();

        // Register default template
        handlebars
            .register_template_string("menuentry", MENUENTRY_TEMPLATE)
            .expect("Failed to register template");

        Self {
            entries: Vec::new(),
            default_entry: None,
            timeout: None,
            handlebars,
        }
    }

    pub fn add_entry(&mut self, entry: MenuEntry) -> &mut Self {
        self.entries.push(entry);
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
            "title": entry.title,
            "kernel_url": entry.kernel_url,
            "kernel_params": entry.kernel_params.join(" "),
            "initrd_url": entry.initrd_url,
        });

        Ok(self.handlebars.render("menuentry", &data)?)
    }
}

impl<'a> Default for GrubMenuBuilder<'a> {
    fn default() -> Self {
        Self::new()
    }
}

const MENUENTRY_TEMPLATE: &str = r#"menuentry "{{title}}" {
    set gfxpayload=keep
    linux  {{{kernel_url}}} {{{kernel_params}}}
    initrd {{{initrd_url}}}
}"#;
