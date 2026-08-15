{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  requests,
}:

# Yandex Disk REST API client. Not in nixpkgs, and needed because rclone's
# yandex backend implements only CleanUp() -- it can empty the trash but
# cannot list or restore from it, which is exactly the direction that matters
# for recovery.
buildPythonPackage rec {
  pname = "yadisk";
  version = "3.4.1";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-F9kJLGVmJEJTvoaUUFv7Urw1HyfOtWBBeY34fYmS05o=";
  };

  build-system = [ setuptools ];

  # `requests` is an optional extra upstream (sync_defaults), but it is what
  # backs the synchronous Client used here, so it is a hard dependency for us.
  dependencies = [ requests ];

  # Upstream's suite drives the live Yandex Disk API and needs a real token.
  doCheck = false;
  pythonImportsCheck = [ "yadisk" ];

  meta = {
    description = "Yandex Disk REST API client library";
    homepage = "https://github.com/ivknv/yadisk";
    license = lib.licenses.lgpl3Plus;
  };
}
