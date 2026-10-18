-- gts9wifi (SM-X710): apps should see exactly the two processed libcamera
-- cameras ("Built-in Front Camera", "Built-in Back Camera").  The raw
-- Qualcomm CAMSS endpoints (acb7000.isp, ~16 V4L2 nodes) and the iris VPU
-- memory-to-memory nodes are not cameras; offering them makes apps open a
-- black or garbled stream.  GStreamer uses the VPU directly, not through
-- PipeWire, so disabling it here does not affect video playback.
table.insert(v4l2_monitor.rules, {
  matches = {
    { { "device.description", "equals", "Qualcomm Camera Subsystem" } },
    { { "device.description", "equals", "Iris Decoder" } },
    { { "device.description", "equals", "Iris Encoder" } },
  },
  apply_properties = {
    ["device.disabled"] = true,
  },
})

-- The libcamera nodes are already Video/Source with good names; make sure of
-- the class and keep the names short and stable.
for _, cam in ipairs({
  { "libcamera_input._base_soc_0_cci_ac16000_i2c-bus_1_camera_21", "Front Camera" },
  { "libcamera_input._base_soc_0_cci_ac15000_i2c-bus_1_camera_21", "Rear Camera" },
}) do
  table.insert(libcamera_monitor.rules, {
    matches = { { { "node.name", "equals", cam[1] } } },
    apply_properties = {
      ["media.class"] = "Video/Source",
      ["node.description"] = cam[2],
    },
  })
end
