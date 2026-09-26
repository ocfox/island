use crate::model::error::MilkError;
use std::io::Write;
use std::path::Path;

pub fn save_to_file<P: AsRef<Path>>(path: P, png_bytes: &[u8]) -> Result<(), MilkError> {
    std::fs::write(path, png_bytes)?;
    Ok(())
}

pub fn write_to_stdout(png_bytes: &[u8]) -> Result<(), MilkError> {
    let stdout = std::io::stdout();
    let mut handle = stdout.lock();
    handle.write_all(png_bytes)?;
    handle.flush()?;
    Ok(())
}
