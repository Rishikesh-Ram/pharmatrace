"""Runs the image-comparison model with graceful fallback if native C++ DLLs are blocked."""
import logging
import os

import numpy as np
from PIL import Image

log = logging.getLogger("pharmatrace.vision")

MODEL_PATH = os.getenv(
    "MODEL_PATH",
    os.path.join(
        os.path.dirname(__file__),
        "..",
        "model",
        "pharmatrace_model.keras",
    ),
)
MODEL_PATH = os.path.abspath(MODEL_PATH)

SIMILARITY_THRESHOLD = float(os.getenv("SIMILARITY_THRESHOLD", "0.80"))
MODEL_RESCALE = os.getenv("MODEL_RESCALE", "true").lower() == "true"


class ModelNotReady(Exception):
    pass


_model = None
_tf_available = None


def is_installed() -> bool:
    return os.path.exists(MODEL_PATH)


def get_model():
    """Loads the model on first use. If the file is not there yet, raises ModelNotReady."""
    global _model, _tf_available
    if _model is not None:
        return _model

    if not is_installed():
        raise ModelNotReady(
            f"Model not installed yet. Place your trained model at '{MODEL_PATH}'."
        )

    try:
        import tensorflow as tf  # type: ignore
        _model = tf.keras.models.load_model(MODEL_PATH)
        _tf_available = True
        return _model
    except Exception as exc:
        _tf_available = False
        log.warning("TensorFlow engine unavailable (%s); using vision feature extractor fallback.", exc)
        return None


def _preprocess(img: Image.Image, size):
    arr = np.asarray(
        img.convert("RGB").resize(size),
        dtype="float32",
    )
    # MobileNetV2 expects pixel values in the range [-1, 1].
    arr = arr / 127.5 - 1.0
    return np.expand_dims(arr, 0)


def _feature_vector(img: Image.Image) -> np.ndarray:
    """Fallback spatial-color feature extraction using PIL and NumPy."""
    rgb = img.convert("RGB").resize((224, 224))
    arr = np.asarray(rgb, dtype=np.float32) / 255.0

    # Color channel histograms (32 bins * 3 channels = 96 features)
    r_hist, _ = np.histogram(arr[:, :, 0], bins=32, range=(0.0, 1.0))
    g_hist, _ = np.histogram(arr[:, :, 1], bins=32, range=(0.0, 1.0))
    b_hist, _ = np.histogram(arr[:, :, 2], bins=32, range=(0.0, 1.0))

    # Spatial block grid averages (4x4 cells * 3 channels = 48 features)
    grid = arr.reshape(4, 56, 4, 56, 3).mean(axis=(1, 3)).flatten()

    features = np.concatenate([r_hist, g_hist, b_hist, grid]).astype(np.float32)
    norm = np.linalg.norm(features)
    return features / (norm + 1e-9)


def similarity(uploaded: Image.Image, reference: Image.Image) -> float:
    """
    0..1 similarity score.
    - If TensorFlow model is loaded: evaluates via model.
    - Otherwise uses robust spatial-color feature vector cosine similarity.
    """
    model = get_model()

    if model is not None:
        try:
            if isinstance(model.input_shape, list) and len(model.input_shape) == 2:
                h, w = model.input_shape[0][1:3]
                a, b = _preprocess(uploaded, (w, h)), _preprocess(reference, (w, h))
                return float(np.ravel(model.predict([a, b], verbose=0))[0])

            h, w = model.input_shape[1:3]
            ea = model.predict(_preprocess(uploaded, (w, h)), verbose=0)[0]
            eb = model.predict(_preprocess(reference, (w, h)), verbose=0)[0]
            cos = float(np.dot(ea, eb) / (np.linalg.norm(ea) * np.linalg.norm(eb) + 1e-9))
            return max(0.0, min(1.0, cos))
        except Exception as e:
            log.warning("Model prediction failed (%s); falling back to feature extractor.", e)

    ea = _feature_vector(uploaded)
    eb = _feature_vector(reference)
    cos = float(np.dot(ea, eb))
    return max(0.0, min(1.0, cos))
