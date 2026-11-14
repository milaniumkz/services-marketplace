/* Local-only landmark and expression inference. No liveness/anti-spoofing claim. */
(function (root) {
  'use strict';
  const assetRoot = '/face-models/mediapipe-0.10.32-v1';
  let visionPromise;
  function metrics(result) {
    const faces = result.faceLandmarks || [];
    if (faces.length !== 1) return {faces: faces.length};
    const points = faces[0], a = points[33], b = points[263], nose = points[1];
    const eyeDistance = Math.hypot(a.x - b.x, a.y - b.y);
    if (!eyeDistance || points.some(p => !Number.isFinite(p.x) || !Number.isFinite(p.y))) return {faces: 0};
    const xs = points.map(p => p.x), ys = points.map(p => p.y);
    const left = Math.min(...xs), right = Math.max(...xs), top = Math.min(...ys), bottom = Math.max(...ys);
    const categories = result.faceBlendshapes?.[0]?.categories || [];
    const score = name => categories.find(c => c.categoryName === name)?.score || 0;
    return {faces: 1, yaw: (nose.x - (a.x + b.x) / 2) / eyeDistance,
      centerX: (left + right) / 2, centerY: (top + bottom) / 2,
      width: right - left, height: bottom - top,
      blinkLeft: score('eyeBlinkLeft'), blinkRight: score('eyeBlinkRight'),
      smile: (score('mouthSmileLeft') + score('mouthSmileRight')) / 2};
  }
  root.jobaCreateFaceTracker = async function () {
    visionPromise ||= import(assetRoot + '/vision_bundle.mjs');
    const vision = await visionPromise;
    const files = await vision.FilesetResolver.forVisionTasks(assetRoot + '/wasm');
    const model = await vision.FaceLandmarker.createFromOptions(files, {
      baseOptions: {modelAssetPath: assetRoot + '/face_landmarker.task', delegate: 'CPU'},
      runningMode: 'VIDEO', numFaces: 2,
      minFaceDetectionConfidence: 0.6, minFacePresenceConfidence: 0.6,
      minTrackingConfidence: 0.6, outputFaceBlendshapes: true,
      outputFacialTransformationMatrixes: false
    });
    let closed = false;
    return {
      detect: (video, timestamp) => {
        if (closed) throw new Error('Face tracker closed');
        return metrics(model.detectForVideo(video, timestamp));
      },
      close: () => {if (!closed) {closed = true; model.close();}}
    };
  };
})(globalThis);
