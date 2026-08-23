"""King's College London institutional paper retrieval.

The last rung of the paper ladder: the only route to post-2021 paywalled
articles, and the only one that touches institutional credentials.

This package must never import ``scansci_pdf``. That package sets
``os.environ["NO_PROXY"] = "*"`` process-wide and monkey-patches
``ssl.SSLContext.load_default_certs`` at import time; either would silently
change how this process reaches KCL's IdP and the publishers. If the two ever
need to cooperate, they cooperate over a subprocess boundary.
"""
