import tensorflow as tf
import numpy as np
import pandas as pd
import os

print("=" * 60)
print("1) best_model.h5")
print("=" * 60)
try:
    m1 = tf.keras.models.load_model("best_model.h5", compile=False)
    size_mb = os.path.getsize("best_model.h5") / 1024 / 1024
    print(f"   Size: {size_mb:.2f} MB")
    print(f"   Input shape:  {m1.input_shape}")
    print(f"   Output shape: {m1.output_shape}")
    print(f"   Layers: {len(m1.layers)}")
    print(f"   Params: {m1.count_params():,}")
    print()
    m1.summary()
    print()

    # Test prediction
    dummy = np.zeros((1, 30, 1662), dtype=np.float32)
    pred = m1.predict(dummy, verbose=0)
    print(f"   Test prediction shape: {pred.shape}")
    print(f"   Num output classes: {pred.shape[-1]}")
    print(f"   Pred sum (softmax check): {pred.sum():.4f}")
    print(f"   Pred max: {pred.max():.4f}")

    # Check against labels
    labels_df = pd.read_excel("KARSL-100_Labels (1).xlsx")
    actions = labels_df["Sign-Arabic"].tolist()
    print(f"\n   Labels file has {len(actions)} classes")
    print(f"   Model output has {pred.shape[-1]} classes")
    if len(actions) == pred.shape[-1]:
        print("   >>> MATCH! Labels count == Model output classes")
    else:
        print(f"   >>> MISMATCH! Labels={len(actions)} vs Model={pred.shape[-1]}")
    print(f"   First 5 labels: {actions[:5]}")
    print(f"   Last 5 labels: {actions[-5:]}")
except Exception as e:
    print(f"   ERROR: {e}")
    import traceback
    traceback.print_exc()

print()
print("=" * 60)
print("2) word_to_sign_model.h5")
print("=" * 60)
try:
    m2 = tf.keras.models.load_model("word_to_sign_model.h5", compile=False)
    size_mb = os.path.getsize("word_to_sign_model.h5") / 1024 / 1024
    print(f"   Size: {size_mb:.2f} MB")
    print(f"   Input shape:  {m2.input_shape}")
    print(f"   Output shape: {m2.output_shape}")
    print(f"   Layers: {len(m2.layers)}")
    print(f"   Params: {m2.count_params():,}")
    print()
    m2.summary()
    print()

    # Try to understand what this model does
    input_shape = m2.input_shape
    output_shape = m2.output_shape
    print(f"   Input shape analysis: {input_shape}")
    print(f"   Output shape analysis: {output_shape}")

    # Check last layer activation
    last_layer = m2.layers[-1]
    print(f"   Last layer: {last_layer.name} ({last_layer.__class__.__name__})")
    if hasattr(last_layer, 'activation'):
        print(f"   Last activation: {last_layer.activation.__name__}")
    if hasattr(last_layer, 'units'):
        print(f"   Last layer units: {last_layer.units}")

except Exception as e:
    print(f"   ERROR: {e}")
    import traceback
    traceback.print_exc()
