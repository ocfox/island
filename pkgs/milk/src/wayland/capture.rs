use crate::model::color::ColorInfo;
use crate::model::error::MilkError;
use crate::model::pixel::Geometry;
use crate::wayland::shm::ShmBuffer;

use wayland_client::protocol::wl_buffer::WlBuffer;
use wayland_client::protocol::wl_output::{self, WlOutput};
use wayland_client::protocol::wl_registry::{self, WlRegistry};
use wayland_client::protocol::wl_shm::Format as WlShmFormat;
use wayland_client::protocol::wl_shm::WlShm;
use wayland_client::protocol::wl_shm_pool::WlShmPool;
use wayland_client::{Connection, Dispatch, EventQueue, QueueHandle, WEnum};

use wayland_protocols::wp::color_management::v1::client::wp_color_management_output_v1::{
    self, WpColorManagementOutputV1,
};
use wayland_protocols::wp::color_management::v1::client::wp_color_manager_v1::{
    self, WpColorManagerV1,
};
use wayland_protocols::wp::color_management::v1::client::wp_image_description_info_v1::{
    self, WpImageDescriptionInfoV1,
};
use wayland_protocols::wp::color_management::v1::client::wp_image_description_v1::{
    self, WpImageDescriptionV1,
};

use wayland_protocols_wlr::screencopy::v1::client::zwlr_screencopy_frame_v1::{
    self, ZwlrScreencopyFrameV1,
};
use wayland_protocols_wlr::screencopy::v1::client::zwlr_screencopy_manager_v1::ZwlrScreencopyManagerV1;

const WL_OUTPUT_VERSION: u32 = 4;
const WL_SHM_VERSION: u32 = 1;
const SCREENCOPY_VERSION: u32 = 3;
const COLOR_MANAGER_VERSION: u32 = 2;

const FLAG_Y_INVERT: u32 = 1;
const OVERLAY_CURSOR_ENABLED: i32 = 1;
const OVERLAY_CURSOR_DISABLED: i32 = 0;

#[derive(Debug, Clone)]
pub struct OutputEntry {
    pub wl_output: WlOutput,
    pub name: Option<String>,
    pub x: i32,
    pub y: i32,
}

#[derive(Debug, Clone, Copy)]
pub struct BufferInfo {
    pub format: u32,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
}

pub struct WaylandState {
    pub outputs: Vec<OutputEntry>,
    pub shm: Option<WlShm>,
    pub screencopy_mgr: Option<ZwlrScreencopyManagerV1>,
    pub color_mgr: Option<WpColorManagerV1>,

    // Screencopy state
    pub frame: Option<ZwlrScreencopyFrameV1>,
    pub buffer_info: Option<BufferInfo>,
    pub shm_buffer: Option<ShmBuffer>,
    pub y_invert: bool,
    pub ready: bool,
    pub failed: bool,

    // Color management state
    pub color_info: ColorInfo,
}

impl WaylandState {
    pub fn new() -> Self {
        Self {
            outputs: Vec::new(),
            shm: None,
            screencopy_mgr: None,
            color_mgr: None,
            frame: None,
            buffer_info: None,
            shm_buffer: None,
            y_invert: false,
            ready: false,
            failed: false,
            color_info: ColorInfo::default(),
        }
    }
}

impl Dispatch<WlRegistry, ()> for WaylandState {
    fn event(
        state: &mut Self,
        registry: &WlRegistry,
        event: wl_registry::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        if let wl_registry::Event::Global {
            name,
            interface,
            version,
        } = event
        {
            match interface.as_str() {
                "wl_output" => {
                    let version = version.min(WL_OUTPUT_VERSION);
                    let output = registry.bind::<WlOutput, _, _>(name, version, qh, ());
                    state.outputs.push(OutputEntry {
                        wl_output: output,
                        name: None,
                        x: 0,
                        y: 0,
                    });
                }
                "wl_shm" => {
                    state.shm = Some(registry.bind::<WlShm, _, _>(name, WL_SHM_VERSION, qh, ()));
                }
                "zwlr_screencopy_manager_v1" => {
                    let version = version.min(SCREENCOPY_VERSION);
                    state.screencopy_mgr =
                        Some(registry.bind::<ZwlrScreencopyManagerV1, _, _>(name, version, qh, ()));
                }
                "wp_color_manager_v1" => {
                    let version = version.min(COLOR_MANAGER_VERSION);
                    state.color_mgr =
                        Some(registry.bind::<WpColorManagerV1, _, _>(name, version, qh, ()));
                }
                _ => {}
            }
        }
    }
}

impl Dispatch<WlOutput, ()> for WaylandState {
    fn event(
        state: &mut Self,
        output: &WlOutput,
        event: wl_output::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        if let Some(entry) = state.outputs.iter_mut().find(|o| &o.wl_output == output) {
            match event {
                wl_output::Event::Name { name } => {
                    entry.name = Some(name);
                }
                wl_output::Event::Geometry { x, y, .. } => {
                    entry.x = x;
                    entry.y = y;
                }
                _ => {}
            }
        }
    }
}

impl Dispatch<WlShm, ()> for WaylandState {
    fn event(
        _: &mut Self,
        _: &WlShm,
        _: wayland_client::protocol::wl_shm::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<WlShmPool, ()> for WaylandState {
    fn event(
        _: &mut Self,
        _: &WlShmPool,
        _: wayland_client::protocol::wl_shm_pool::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<WlBuffer, ()> for WaylandState {
    fn event(
        _: &mut Self,
        _: &WlBuffer,
        _: wayland_client::protocol::wl_buffer::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ZwlrScreencopyManagerV1, ()> for WaylandState {
    fn event(
        _: &mut Self,
        _: &ZwlrScreencopyManagerV1,
        _: wayland_protocols_wlr::screencopy::v1::client::zwlr_screencopy_manager_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<ZwlrScreencopyFrameV1, ()> for WaylandState {
    fn event(
        state: &mut Self,
        frame: &ZwlrScreencopyFrameV1,
        event: zwlr_screencopy_frame_v1::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match event {
            zwlr_screencopy_frame_v1::Event::Buffer {
                format,
                width,
                height,
                stride,
            } => {
                let fourcc: u32 = match format {
                    WEnum::Value(fmt) => fmt as u32,
                    WEnum::Unknown(val) => val,
                };

                let shm_format = match format {
                    WEnum::Value(fmt) => fmt,
                    WEnum::Unknown(val) => match WlShmFormat::try_from(val) {
                        Ok(f) => f,
                        Err(_) => {
                            eprintln!("Unknown buffer format {val:#x}");
                            state.failed = true;
                            return;
                        }
                    },
                };

                state.buffer_info = Some(BufferInfo {
                    format: fourcc,
                    width,
                    height,
                    stride,
                });

                if let Some(shm) = &state.shm {
                    match ShmBuffer::new(
                        shm,
                        width as i32,
                        height as i32,
                        stride as i32,
                        shm_format,
                        qh,
                    ) {
                        Ok(shm_buf) => {
                            frame.copy(shm_buf.wl_buffer());
                            state.shm_buffer = Some(shm_buf);
                        }
                        Err(e) => {
                            eprintln!("Failed to allocate ShmBuffer: {e}");
                            state.failed = true;
                        }
                    }
                }
            }
            zwlr_screencopy_frame_v1::Event::Flags { flags } => {
                let y_invert = match flags {
                    WEnum::Value(f) => f.contains(zwlr_screencopy_frame_v1::Flags::YInvert),
                    WEnum::Unknown(u) => (u & FLAG_Y_INVERT) != 0,
                };
                state.y_invert = y_invert;
            }
            zwlr_screencopy_frame_v1::Event::Ready { .. } => {
                state.ready = true;
            }
            zwlr_screencopy_frame_v1::Event::Failed => {
                state.failed = true;
            }
            _ => {}
        }
    }
}

impl Dispatch<WpColorManagerV1, ()> for WaylandState {
    fn event(
        _: &mut Self,
        _: &WpColorManagerV1,
        _: wp_color_manager_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<WpColorManagementOutputV1, ()> for WaylandState {
    fn event(
        _: &mut Self,
        _: &WpColorManagementOutputV1,
        _: wp_color_management_output_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

impl Dispatch<WpImageDescriptionV1, ()> for WaylandState {
    fn event(
        _: &mut Self,
        image_desc: &WpImageDescriptionV1,
        event: wp_image_description_v1::Event,
        _: &(),
        _: &Connection,
        qh: &QueueHandle<Self>,
    ) {
        match event {
            wp_image_description_v1::Event::Ready { .. }
            | wp_image_description_v1::Event::Ready2 { .. } => {
                // When image_desc is ready, request information
                let _info = image_desc.get_information(qh, ());
            }
            wp_image_description_v1::Event::Failed { .. } => {
                // Failed: leave color info unset (treated as sRGB)
            }
            _ => {}
        }
    }
}

impl Dispatch<WpImageDescriptionInfoV1, ()> for WaylandState {
    fn event(
        state: &mut Self,
        _info: &WpImageDescriptionInfoV1,
        event: wp_image_description_info_v1::Event,
        _: &(),
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
        match event {
            wp_image_description_info_v1::Event::TfNamed { tf } => {
                let val: u32 = match tf {
                    WEnum::Value(v) => v as u32,
                    WEnum::Unknown(u) => u,
                };
                state.color_info.tf_named = val;
                state.color_info.has_tf = true;
            }
            wp_image_description_info_v1::Event::PrimariesNamed { primaries } => {
                let val: u32 = match primaries {
                    WEnum::Value(v) => v as u32,
                    WEnum::Unknown(u) => u,
                };
                state.color_info.primaries_named = val;
                state.color_info.has_primaries = true;
            }
            wp_image_description_info_v1::Event::Luminances {
                max_lum,
                reference_lum,
                ..
            } => {
                state.color_info.max_lum = max_lum as f64;
                state.color_info.reference_lum = reference_lum as f64;
                state.color_info.has_luminances = true;
            }
            wp_image_description_info_v1::Event::Done => {}
            _ => {}
        }
    }
}

pub struct CaptureSession {
    pub event_queue: EventQueue<WaylandState>,
    pub qh: QueueHandle<WaylandState>,
    pub state: WaylandState,
}

impl CaptureSession {
    pub fn connect() -> Result<Self, MilkError> {
        let conn =
            Connection::connect_to_env().map_err(|e| MilkError::WaylandConnect(e.to_string()))?;

        let mut event_queue = conn.new_event_queue();
        let qh = event_queue.handle();
        let mut state = WaylandState::new();

        // Bind registry and discover globals
        let _registry = conn.display().get_registry(&qh, ());
        event_queue
            .roundtrip(&mut state)
            .map_err(|e| MilkError::WaylandConnect(e.to_string()))?;

        // Roundtrip again to receive output names and initial events
        event_queue
            .roundtrip(&mut state)
            .map_err(|e| MilkError::WaylandConnect(e.to_string()))?;

        if state.shm.is_none() {
            return Err(MilkError::MissingGlobal("wl_shm"));
        }
        if state.screencopy_mgr.is_none() {
            return Err(MilkError::MissingGlobal("zwlr_screencopy_manager_v1"));
        }

        Ok(Self {
            event_queue,
            qh,
            state,
        })
    }

    pub fn query_color_info(&mut self, output: &WlOutput) -> ColorInfo {
        if let Some(color_mgr) = &self.state.color_mgr {
            let cm_output = color_mgr.get_output(output, &self.qh, ());
            let img_desc = cm_output.get_image_description(&self.qh, ());

            // Roundtrip 1: wait for image_desc ready event (which calls get_information)
            let _ = self.event_queue.roundtrip(&mut self.state);
            // Roundtrip 2: wait for image_desc_info events (TfNamed, Primaries, Luminances, Done)
            let _ = self.event_queue.roundtrip(&mut self.state);

            cm_output.destroy();
            img_desc.destroy();
        }

        self.state.color_info
    }

    pub fn capture(
        mut self,
        target_output_name: Option<&str>,
        overlay_cursor: bool,
        geometry: Option<&Geometry>,
    ) -> Result<(ShmBuffer, BufferInfo, bool, ColorInfo), MilkError> {
        // Select output
        let (output_wl, out_x, out_y) = if let Some(name) = target_output_name {
            self.state
                .outputs
                .iter()
                .find(|o| o.name.as_deref() == Some(name))
                .map(|o| (o.wl_output.clone(), o.x, o.y))
                .ok_or_else(|| MilkError::OutputNotFound(name.to_string()))?
        } else {
            self.state
                .outputs
                .first()
                .map(|o| (o.wl_output.clone(), o.x, o.y))
                .ok_or_else(|| {
                    MilkError::CaptureFailed("No Wayland outputs detected".to_string())
                })?
        };

        // Query color management for the selected output
        let color_info = self.query_color_info(&output_wl);

        let screencopy_mgr = self
            .state
            .screencopy_mgr
            .as_ref()
            .ok_or(MilkError::MissingGlobal("zwlr_screencopy_manager_v1"))?;

        let overlay = if overlay_cursor {
            OVERLAY_CURSOR_ENABLED
        } else {
            OVERLAY_CURSOR_DISABLED
        };

        // Start capture: if geometry is specified, use capture_output_region
        let frame = if let Some(geom) = geometry {
            let local_x = geom.x - out_x;
            let local_y = geom.y - out_y;
            screencopy_mgr.capture_output_region(
                overlay,
                &output_wl,
                local_x,
                local_y,
                geom.width as i32,
                geom.height as i32,
                &self.qh,
                (),
            )
        } else {
            screencopy_mgr.capture_output(overlay, &output_wl, &self.qh, ())
        };

        self.state.frame = Some(frame);

        // Run event loop until capture is ready or failed
        while !self.state.ready && !self.state.failed {
            self.event_queue
                .blocking_dispatch(&mut self.state)
                .map_err(|e| MilkError::CaptureFailed(e.to_string()))?;
        }

        if self.state.failed {
            return Err(MilkError::CaptureFailed(
                "Compositor reported frame failed".to_string(),
            ));
        }

        let buffer_info = self
            .state
            .buffer_info
            .ok_or_else(|| MilkError::CaptureFailed("No buffer event received".to_string()))?;

        let shm_buf = self
            .state
            .shm_buffer
            .take()
            .ok_or_else(|| MilkError::CaptureFailed("No SHM buffer allocated".to_string()))?;

        if let Some(frame) = self.state.frame.take() {
            frame.destroy();
        }

        Ok((shm_buf, buffer_info, self.state.y_invert, color_info))
    }
}
