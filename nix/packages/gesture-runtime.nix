{ pkgs }:

let
  platform =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      {
        mediapipeWheel = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/2a/58/bdd5bada89d7a132375df05e962bf702c148b47043dca98d820d9395152b/mediapipe-1.0.1-py3-none-manylinux_2_28_x86_64.whl";
          hash = "sha256-EhUiJRr8PBNeS3sMNB3V4FCtHsh2MRJ0hPPDia44UEQ=";
        };
        onnxRuntime = pkgs.fetchurl {
          url = "https://github.com/microsoft/onnxruntime/releases/download/v1.23.2/onnxruntime-linux-x64-1.23.2.tgz";
          hash = "sha256-H6TcrvIvb31c2BsowoAEFDUMEBFvX91GohYAglUcX5s=";
        };
        onnxRuntimeDirectory = "onnxruntime-linux-x64-1.23.2";
      }
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      {
        mediapipeWheel = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/16/9d/515c6ebc98db21484b2b93b7403464d08fb7861b6430752801bc75d29372/mediapipe-1.0.1-py3-none-manylinux_2_28_aarch64.whl";
          hash = "sha256-1gUOdz3GaY64YyQJD2GvHMqyim8en3fZj+BhHO9weZc=";
        };
        onnxRuntime = pkgs.fetchurl {
          url = "https://github.com/microsoft/onnxruntime/releases/download/v1.23.2/onnxruntime-linux-aarch64-1.23.2.tgz";
          hash = "sha256-fGPHNWDtdrH6xs/4IE/+NP4YDnDWWCtTMuwJSBAkHlw=";
        };
        onnxRuntimeDirectory = "onnxruntime-linux-aarch64-1.23.2";
      }
    else
      throw "singularity gesture runtime does not support ${pkgs.stdenv.hostPlatform.system}";

  handLandmarker = pkgs.fetchurl {
    url = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task";
    hash = "sha256-+8KjAIDDxVcJO13fwzRpgTLrNBBEzO4yLM+LzzYHzeE=";
  };
  faceLandmarker = pkgs.fetchurl {
    url = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";
    hash = "sha256-ZBhOIpsmMQe8K4BMZiXbE0H/K7cxh0sLzC/mVE4Lyf8=";
  };
  gazeModel = pkgs.fetchurl {
    url = "https://github.com/yakhyo/gaze-estimation/releases/download/weights/mobileone_s0_gaze.onnx";
    hash = "sha256-i0/cTj2kRzPJqC53drQR5KOflOjiha7g/IWlSKVffZ8=";
  };
in
pkgs.runCommand "singularity-gesture-runtime" {
  nativeBuildInputs = with pkgs; [
    gnutar
    gzip
    unzip
  ];
} ''
  mkdir -p "$out/include" unpacked

  unzip -p ${platform.mediapipeWheel} \
    mediapipe/tasks/c/libmediapipe.so > "$out/libmediapipe.so"

  tar -xzf ${platform.onnxRuntime} -C unpacked
  onnx_dir="unpacked/${platform.onnxRuntimeDirectory}"
  cp "$onnx_dir/lib/libonnxruntime.so.1.23.2" "$out/libonnxruntime.so"
  cp "$onnx_dir/include/onnxruntime_c_api.h" "$out/include/"
  cp "$onnx_dir/include/onnxruntime_ep_c_api.h" "$out/include/"

  cp ${handLandmarker} "$out/hand_landmarker.task"
  cp ${faceLandmarker} "$out/face_landmarker.task"
  cp ${gazeModel} "$out/mobileone_s0_gaze.onnx"
''
