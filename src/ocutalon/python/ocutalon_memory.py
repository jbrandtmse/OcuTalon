"""Calls into fastembed and huggingface_hub for OcuTalon's memory embeddings (AD-6, AD-21).

ObjectScript's %SYS.Python on build 154 passes no keyword arguments, so the two calls that need them live
here. Both run only in a worker of the WorkMgr category OcuTalon.Memory.Embedder, imported with
%SYS.Python.Import by OcuTalon.Memory.Embedder. This module holds no user-facing text and makes no call by
itself.
"""


def load_model(model, folder):
    """Return fastembed.TextEmbedding(model) that reads the model from folder only (no network try)."""
    import fastembed

    return fastembed.TextEmbedding(model, cache_dir=folder, local_files_only=True)


def download(source, folder, patterns):
    """Download the files of the Hugging Face repository source that match patterns into folder; return the snapshot folder."""
    import huggingface_hub

    return huggingface_hub.snapshot_download(source, cache_dir=folder, allow_patterns=list(patterns))
