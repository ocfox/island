mod model;
mod output;
mod png;
mod transform;
mod wayland;

use argh::FromArgs;
use model::error::MilkError;
use model::frame::RawFrame;
use model::pixel::{Geometry, PixelFormat};
use output::{save_to_file, write_to_stdout};
use png::encode_png;
use std::time::Instant;
use transform::process_raw_frame;
use wayland::CaptureSession;

const BYTES_PER_MIB: f64 = 1024.0 * 1024.0;
const MS_PER_SEC: f64 = 1000.0;

/// High-performance Wayland screenshot utility.
#[derive(FromArgs, Debug)]
struct Args {
    /// composite cursor onto the screenshot
    #[argh(switch, short = 'c')]
    cursor: bool,

    /// capture a specific geometry (e.g. "X,Y WxH" from slurp)
    #[argh(option, short = 'g')]
    geometry: Option<String>,

    /// capture a specific Wayland output (e.g. "DP-2")
    #[argh(option, short = 'o')]
    output: Option<String>,

    /// output scale factor (accepted for compatibility with grim)
    #[argh(option, short = 's')]
    _scale: Option<f64>,

    /// zlib compression level (1-9, default: 1 for sub-100ms 4K encoding)
    #[argh(option, short = 'l', default = "1")]
    level: u32,

    /// write raw PNG bytes directly to standard output
    #[argh(switch, long = "stdout")]
    stdout: bool,

    /// output file path (or '-' for stdout)
    #[argh(positional)]
    target: Option<String>,
}

fn run(args: Args) -> Result<(), MilkError> {
    if args.target.is_none() && !args.stdout {
        return Err(MilkError::NoOutputSpecified);
    }

    let start = Instant::now();

    let geometry = args
        .geometry
        .as_deref()
        .map(str::parse::<Geometry>)
        .transpose()?;

    let session = CaptureSession::connect()?;
    let (shm_buf, buf_info, y_invert, color_info) =
        session.capture(args.output.as_deref(), args.cursor, geometry.as_ref())?;

    let capture_elapsed = start.elapsed();

    let pixel_format = PixelFormat::from_fourcc(buf_info.format);
    if let PixelFormat::Unsupported(fourcc) = pixel_format {
        return Err(MilkError::UnsupportedFormat(fourcc));
    }

    let raw_frame = RawFrame {
        data: shm_buf.as_slice(),
        width: buf_info.width,
        height: buf_info.height,
        stride: buf_info.stride,
        format: pixel_format,
        y_invert,
    };

    let t_transform = Instant::now();
    let rgba = process_raw_frame(&raw_frame, &color_info)?;
    let transform_elapsed = t_transform.elapsed();

    let t_encode = Instant::now();
    let png_bytes = encode_png(&rgba, args.level)?;
    let encode_elapsed = t_encode.elapsed();

    let total_elapsed = start.elapsed();

    if args.stdout {
        write_to_stdout(&png_bytes)?;
    } else if let Some(ref target) = args.target {
        save_to_file(target, &png_bytes)?;
        eprintln!(
            "milk: saved {}x{} PNG ({:.2} MB) to '{}' in {:.1}ms (cap: {:.1}ms, xform: {:.1}ms, png: {:.1}ms)",
            rgba.width,
            rgba.height,
            png_bytes.len() as f64 / BYTES_PER_MIB,
            target,
            total_elapsed.as_secs_f64() * MS_PER_SEC,
            capture_elapsed.as_secs_f64() * MS_PER_SEC,
            transform_elapsed.as_secs_f64() * MS_PER_SEC,
            encode_elapsed.as_secs_f64() * MS_PER_SEC,
        );
    }

    Ok(())
}

fn main() {
    let mut raw_args: Vec<String> = std::env::args().collect();
    for arg in raw_args.iter_mut().skip(1) {
        if arg == "-" {
            *arg = "--stdout".to_string();
        } else if arg == "-h" {
            *arg = "--help".to_string();
        }
    }

    let cmd_name = raw_args.first().map_or("milk", String::as_str);
    let arg_refs: Vec<&str> = raw_args.iter().skip(1).map(String::as_str).collect();

    let args: Args = match Args::from_args(&[cmd_name], &arg_refs) {
        Ok(a) => a,
        Err(err) => {
            eprintln!("{}", err.output);
            std::process::exit(match err.status {
                Ok(_) => 0,
                Err(_) => 1,
            });
        }
    };

    if let Err(e) = run(args) {
        eprintln!("milk error: {e}");
        std::process::exit(1);
    }
}
