"""Runs the image-comparison model. The model can be added after the app is running."""
import os

import numpy as np
from PIL import Image

MODEL_PATH = os.getenv("MODEL_PATH", "model/pharmatrace_model.keras")
SIMILARITY_THRESHOLD = float(os.getenv("SIMILARITY_THRESHOLD", "0.80"))
MODEL_RESCALE = os.getenv("MODEL_RESCALE", "true").lower() == "true"


class ModelNotReady(Exception):
    pass


_model = None


def is_installed() -> bool:
    return os.path.exists(MODEL_PATH)


def get_model():
    """Loads the model on first use. If the file is not there yet, raises ModelNotReady;
    drop the file into place and the next request loads it (no restart needed)."""
    global _model
    if _model is None:
        if not is_installed():
            raise ModelNotReady(
                f"Model not installed yet. Place your trained model at '{MODEL_PATH}'."
            )
        import tensorflow as tf
        _model = tf.keras.models.load_model(MODEL_PATH)
    return _model


def _preprocess(img: Image.Image, size):
    arr = np.asarray(img.convert("RGB").resize(size), dtype="float32")
    if MODEL_RESCALE:
        arr /= 255.0
    return np.expand_dims(arr, 0)


def similarity(uploaded: Image.Image, reference: Image.Image) -> float:
    """
    0..1 similarity score.
    - Two-input (siamese) model: its output is the score.
    - Otherwise the output vector is an embedding; cosine similarity is used.
    """
    model = get_model()
    if isinstance(model.input_shape, list) and len(model.input_shape) == 2:
        h, w = model.input_shape[0][1:3]
        a, b = _preprocess(uploaded, (w, h)), _preprocess(reference, (w, h))
        return float(np.ravel(model.predict([a, b], verbose=0))[0])

    h, w = model.input_shape[1:3]
    ea = model.predict(_preprocess(uploaded, (w, h)), verbose=0)[0]
    eb = model.predict(_preprocess(reference, (w, h)), verbose=0)[0]
    cos = float(np.dot(ea, eb) / (np.linalg.norm(ea) * np.linalg.norm(eb) + 1e-9))
    return max(0.0, min(1.0, cos))
