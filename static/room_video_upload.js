const ROOM_VIDEO_TUS_CHUNK_SIZE = 6 * 1024 * 1024;
const ROOM_VIDEO_RETRY_DELAYS = [1000, 3000, 5000, 10000, 20000];

function roomVideoTusRequest(method, url, headers, body, onProgress) {
  return new Promise((resolve, reject) => {
    const request = new XMLHttpRequest();
    request.open(method, url);
    request.timeout = 600000;
    Object.entries(headers).forEach(([name, value]) => {
      request.setRequestHeader(name, value);
    });
    if (onProgress) {
      request.upload.onprogress = onProgress;
    }
    request.onload = () => {
      if (request.status >= 200 && request.status < 300) {
        resolve(request);
        return;
      }
      let detail = "";
      try {
        const response = JSON.parse(request.responseText);
        detail = response.message || response.error || response.details || "";
      } catch {
        detail = request.responseText.trim().slice(0, 240);
      }
      const error = new Error(
        `Upload request failed (HTTP ${request.status})` +
        `${detail ? `: ${detail}` : "."}`
      );
      error.status = request.status;
      reject(error);
    };
    request.onerror = () => reject(new Error("Network connection interrupted."));
    request.ontimeout = () => reject(new Error("Upload request timed out."));
    request.onabort = () => reject(new Error("Upload was cancelled."));
    request.send(body);
  });
}

function roomVideoTusHeaders(token) {
  return {
    "Tus-Resumable": "1.0.0",
    "x-signature": token
  };
}

function roomVideoBase64(value) {
  return btoa(new TextEncoder().encode(value).reduce(
    (encoded, byte) => encoded + String.fromCharCode(byte),
    ""
  ));
}

async function roomVideoUploadChunked(file, uploadDetails, storageKey, progress, status) {
  const headers = roomVideoTusHeaders(uploadDetails.token);
  let uploadUrl = uploadDetails.upload_url || "";
  let offset = 0;

  if (uploadUrl) {
    try {
      const resumed = await roomVideoTusRequest(
        "HEAD", uploadUrl, headers, null
      );
      offset = Number(resumed.getResponseHeader("Upload-Offset"));
      if (!Number.isFinite(offset) || offset < 0 || offset > file.size) {
        throw new Error("Storage returned an invalid upload position.");
      }
      progress.value = Math.floor(offset * 100 / file.size);
    } catch {
      uploadUrl = "";
      offset = 0;
    }
  }

  if (!uploadUrl) {
    const metadata = [
      ["bucketName", "room-photos"],
      ["objectName", uploadDetails.path],
      ["contentType", file.type || (
        file.name.toLowerCase().endsWith(".mov")
          ? "video/quicktime"
          : "video/mp4"
      )],
      ["cacheControl", "3600"]
    ].map(([key, value]) => `${key} ${roomVideoBase64(value)}`).join(",");
    const created = await roomVideoTusRequest(
      "POST",
      uploadDetails.resumable_endpoint,
      {
        ...headers,
        "Upload-Length": file.size.toString(),
        "Upload-Metadata": metadata
      },
      null
    );
    const location = created.getResponseHeader("Location");
    if (!location) {
      throw new Error("Storage did not return a resumable upload URL.");
    }
    uploadUrl = new URL(location, uploadDetails.resumable_endpoint).toString();
    uploadDetails.upload_url = uploadUrl;
  }

  while (offset < file.size) {
    const chunkEnd = Math.min(offset + ROOM_VIDEO_TUS_CHUNK_SIZE, file.size);
    let attempts = 0;
    while (true) {
      try {
        const patched = await roomVideoTusRequest(
          "PATCH",
          uploadUrl,
          {
            ...headers,
            "Upload-Offset": offset.toString(),
            "Content-Type": "application/offset+octet-stream"
          },
          file.slice(offset, chunkEnd),
          (event) => {
            if (!event.lengthComputable) return;
            const uploaded = Math.min(offset + event.loaded, file.size);
            progress.value = Math.floor(uploaded * 100 / file.size);
            status.textContent =
              `Uploading room video... ${progress.value}%`;
          }
        );
        const nextOffset = Number(
          patched.getResponseHeader("Upload-Offset")
        );
        if (nextOffset !== chunkEnd) {
          throw new Error("Storage confirmed an unexpected upload position.");
        }
        offset = nextOffset;
        break;
      } catch (error) {
        if (attempts >= ROOM_VIDEO_RETRY_DELAYS.length) throw error;
        const delay = ROOM_VIDEO_RETRY_DELAYS[attempts];
        attempts += 1;
        status.textContent =
          `Connection interrupted. Resuming upload (${attempts}/` +
          `${ROOM_VIDEO_RETRY_DELAYS.length})...`;
        await new Promise((resolve) => setTimeout(resolve, delay));
        const resumed = await roomVideoTusRequest(
          "HEAD", uploadUrl, headers, null
        );
        const serverOffset = Number(
          resumed.getResponseHeader("Upload-Offset")
        );
        if (
          !Number.isFinite(serverOffset)
          || serverOffset < 0
          || serverOffset > file.size
        ) {
          throw new Error("Storage returned an invalid upload position.");
        }
        offset = serverOffset;
        progress.value = Math.floor(offset * 100 / file.size);
        if (offset >= file.size) break;
      }
    }
  }

  localStorage.removeItem(storageKey);
}

document.querySelectorAll("[data-room-video-upload]").forEach((form) => {
  const videoInput = form.querySelector('input[name="video"]');
  const photosInput = form.querySelector("[data-room-photos]");
  const videoPathInput = form.querySelector('input[name="video_path"]');
  const durationInput = form.querySelector('input[name="video_duration"]');
  const progress = form.querySelector("progress");
  const status = form.querySelector(".room-video-upload-status");
  const submitButton = form.querySelector('button[type="submit"]');
  const photoStatus = form.querySelector(".room-photo-selection-status");

  photosInput.addEventListener("change", () => {
    const count = photosInput.files.length;
    photoStatus.textContent = count
      ? `${count} room photo${count === 1 ? "" : "s"} selected.`
      : "";
  });

  form.addEventListener("submit", async (event) => {
    const file = videoInput.files[0];
    if (!file || form.dataset.videoPrepared === "true") return;
    if (!form.dataset.uploadUrl) return;
    event.preventDefault();
    if (form.dataset.uploading === "true") return;

    const contentType = file.name.toLowerCase().endsWith(".mov")
      ? "video/quicktime"
      : "video/mp4";
    if (file.size > 100 * 1024 * 1024) {
      status.textContent = "The room video must be 100 MB or smaller.";
      return;
    }

    form.dataset.uploading = "true";
    submitButton.disabled = true;
    progress.hidden = false;
    progress.value = 0;
    status.textContent = "Checking video duration...";

    let objectUrl;
    const storageKey = [
      "room-video-tus",
      form.action,
      file.name,
      file.size,
      file.lastModified
    ].join(":");
    try {
      const duration = await new Promise((resolve, reject) => {
        const probe = document.createElement("video");
        objectUrl = URL.createObjectURL(file);
        probe.preload = "metadata";
        probe.onloadedmetadata = () => resolve(probe.duration);
        probe.onerror = () => reject(
          new Error("This browser could not read the video duration.")
        );
        probe.src = objectUrl;
      });
      if (!Number.isFinite(duration) || duration <= 0 || duration > 180) {
        throw new Error("The room video must be 3 minutes or shorter.");
      }

      status.textContent = "Preparing secure upload...";
      let uploadDetails;
      try {
        uploadDetails = JSON.parse(localStorage.getItem(storageKey));
      } catch {
        uploadDetails = null;
      }
      if (!uploadDetails) {
        const prepared = await fetch(form.dataset.uploadUrl, {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({
            filename: file.name,
            content_type: contentType,
            size: file.size
          })
        });
        uploadDetails = await prepared.json();
        if (!prepared.ok) {
          throw new Error(
            uploadDetails.error || "Could not prepare the video upload."
          );
        }
        localStorage.setItem(storageKey, JSON.stringify(uploadDetails));
      }

      await roomVideoUploadChunked(
        file, uploadDetails, storageKey, progress, status
      );

      videoPathInput.value = uploadDetails.path;
      durationInput.value = duration.toString();
      videoInput.value = "";
      form.dataset.videoPrepared = "true";
      status.textContent = "Video uploaded. Saving room media...";
      form.dataset.uploading = "false";
      submitButton.disabled = false;
      form.requestSubmit(submitButton);
    } catch (error) {
      if (error.status === 400) {
        localStorage.removeItem(storageKey);
      }
      const message = error.message || "Video upload failed. Please retry.";
      status.textContent = /mime type .* is not supported/i.test(message)
        ? `${message} Run the MOV storage migration in the Rooms Supabase project.`
        : message;
      form.dataset.uploading = "false";
      submitButton.disabled = false;
      progress.hidden = true;
    } finally {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    }
  });
});
