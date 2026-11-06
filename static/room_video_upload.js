document.querySelectorAll("[data-room-video-upload]").forEach((form) => {
  const videoInput = form.querySelector('input[name="video"]');
  const videoPathInput = form.querySelector('input[name="video_path"]');
  const durationInput = form.querySelector('input[name="video_duration"]');
  const progress = form.querySelector("progress");
  const status = form.querySelector(".room-video-upload-status");
  const submitButton = form.querySelector('button[type="submit"]');

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
      const prepared = await fetch(form.dataset.uploadUrl, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          filename: file.name,
          content_type: contentType,
          size: file.size
        })
      });
      const uploadDetails = await prepared.json();
      if (!prepared.ok) {
        throw new Error(uploadDetails.error || "Could not prepare the video upload.");
      }

      await new Promise((resolve, reject) => {
        const upload = new XMLHttpRequest();
        upload.open("PUT", uploadDetails.signed_url);
        upload.timeout = 600000;
        upload.upload.onprogress = (progressEvent) => {
          if (!progressEvent.lengthComputable) return;
          progress.value = Math.round(
            progressEvent.loaded * 100 / progressEvent.total
          );
          status.textContent = `Uploading room video... ${progress.value}%`;
        };
        upload.onload = () => {
          if (upload.status >= 200 && upload.status < 300) {
            resolve();
          } else {
            reject(new Error("Video upload failed. Please retry."));
          }
        };
        upload.onerror = () => reject(
          new Error("Connection interrupted. Please retry the video upload.")
        );
        upload.onabort = () => reject(
          new Error("Video upload cancelled.")
        );
        upload.ontimeout = () => reject(
          new Error("Video upload timed out. Please retry.")
        );
        const body = new FormData();
        body.append("cacheControl", "3600");
        body.append(
          "file",
          new Blob([file], {type: contentType}),
          file.name
        );
        upload.send(body);
      });

      videoPathInput.value = uploadDetails.path;
      durationInput.value = duration.toString();
      videoInput.value = "";
      form.dataset.videoPrepared = "true";
      status.textContent = "Video uploaded. Saving room media...";
      form.dataset.uploading = "false";
      submitButton.disabled = false;
      form.requestSubmit(submitButton);
    } catch (error) {
      status.textContent = error.message || "Video upload failed. Please retry.";
      form.dataset.uploading = "false";
      submitButton.disabled = false;
      progress.hidden = true;
    } finally {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    }
  });
});
