use crate::model::error::MilkError;
use rustix::fs::{MemfdFlags, ftruncate, memfd_create};
use rustix::mm::{MapFlags, ProtFlags, mmap, munmap};
use std::num::NonZeroUsize;
use std::os::fd::{AsFd, OwnedFd};
use std::ptr::NonNull;
use wayland_client::protocol::wl_buffer::WlBuffer;
use wayland_client::protocol::wl_shm::Format as WlShmFormat;
use wayland_client::protocol::wl_shm::WlShm;
use wayland_client::protocol::wl_shm_pool::WlShmPool;
use wayland_client::{Dispatch, QueueHandle};

pub struct ShmBuffer {
    ptr: NonNull<u8>,
    size: usize,
    _pool: WlShmPool,
    buffer: WlBuffer,
    _fd: OwnedFd,
}

// Safety: The buffer is owned and memory-mapped.
unsafe impl Send for ShmBuffer {}
unsafe impl Sync for ShmBuffer {}

impl ShmBuffer {
    pub fn new<State>(
        shm: &WlShm,
        width: i32,
        height: i32,
        stride: i32,
        format: WlShmFormat,
        qh: &QueueHandle<State>,
    ) -> Result<Self, MilkError>
    where
        State: Dispatch<WlShmPool, ()> + Dispatch<WlBuffer, ()> + 'static,
    {
        let size = (stride as usize)
            .checked_mul(height as usize)
            .ok_or_else(|| MilkError::CaptureFailed("SHM buffer size overflow".to_string()))?;

        let fd = memfd_create(c"milk-shm", MemfdFlags::CLOEXEC | MemfdFlags::ALLOW_SEALING)?;

        ftruncate(&fd, size as u64)?;

        let non_zero_len = NonZeroUsize::new(size)
            .ok_or_else(|| MilkError::CaptureFailed("SHM buffer length cannot be 0".to_string()))?;

        let mmap_ptr = unsafe {
            mmap(
                core::ptr::null_mut(),
                non_zero_len.into(),
                ProtFlags::READ | ProtFlags::WRITE,
                MapFlags::SHARED,
                &fd,
                0,
            )?
        };

        let ptr = NonNull::new(mmap_ptr as *mut u8)
            .ok_or_else(|| MilkError::CaptureFailed("mmap returned null pointer".to_string()))?;

        let pool = shm.create_pool(fd.as_fd(), size as i32, qh, ());
        let wl_buffer = pool.create_buffer(0, width, height, stride, format, qh, ());

        Ok(Self {
            ptr,
            size,
            _pool: pool,
            buffer: wl_buffer,
            _fd: fd,
        })
    }

    #[inline]
    pub fn wl_buffer(&self) -> &WlBuffer {
        &self.buffer
    }

    #[inline]
    pub fn as_slice(&self) -> &[u8] {
        unsafe { core::slice::from_raw_parts(self.ptr.as_ptr(), self.size) }
    }
}

impl Drop for ShmBuffer {
    fn drop(&mut self) {
        unsafe {
            let _ = munmap(self.ptr.as_ptr() as *mut _, self.size);
        }
        self.buffer.destroy();
    }
}
