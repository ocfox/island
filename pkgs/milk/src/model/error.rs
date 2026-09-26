use std::fmt;

#[derive(Debug)]
pub enum MilkError {
    WaylandConnect(String),
    MissingGlobal(&'static str),
    OutputNotFound(String),
    CaptureFailed(String),
    UnsupportedFormat(u32),
    InvalidGeometry(String),
    Io(std::io::Error),
    Compression(String),
    NoOutputSpecified,
}

impl fmt::Display for MilkError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::WaylandConnect(msg) => {
                write!(f, "Failed to connect to Wayland compositor: {msg}")
            }
            Self::MissingGlobal(name) => {
                write!(f, "Compositor missing required Wayland global: {name}")
            }
            Self::OutputNotFound(name) => write!(f, "Target output '{name}' not found"),
            Self::CaptureFailed(msg) => write!(f, "Screencopy frame capture failed: {msg}"),
            Self::UnsupportedFormat(fourcc) => {
                let bytes = fourcc.to_le_bytes();
                let fourcc_str = String::from_utf8_lossy(&bytes);
                write!(
                    f,
                    "Unsupported pixel format {fourcc:#010x} ('{fourcc_str}')"
                )
            }
            Self::InvalidGeometry(s) => {
                write!(f, "Invalid geometry format '{s}'. Expected 'X,Y WxH'")
            }
            Self::Io(err) => write!(f, "I/O error: {err}"),
            Self::Compression(msg) => write!(f, "PNG compression error: {msg}"),
            Self::NoOutputSpecified => write!(
                f,
                "No output target specified. Provide an output file path or use '-' for stdout."
            ),
        }
    }
}

impl std::error::Error for MilkError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(err) => Some(err),
            _ => None,
        }
    }
}

impl From<std::io::Error> for MilkError {
    fn from(err: std::io::Error) -> Self {
        Self::Io(err)
    }
}

impl From<rustix::io::Errno> for MilkError {
    fn from(err: rustix::io::Errno) -> Self {
        Self::Io(err.into())
    }
}
