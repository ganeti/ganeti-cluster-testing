import os

QA_ROOT = os.environ.get("GANETI_QA_ROOT", "/var/lib/ganeti-qa")
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RECIPES_DIR = os.path.join(REPO_ROOT, "qa-configs")

LIST_RUNS_DEFAULT_LIMIT = 50
LIST_RUNS_MAX_LIMIT = 500

READ_LOG_DEFAULT_LINES = 500
READ_LOG_MAX_LINES = 2000
READ_LOG_MAX_BYTES = 256 * 1024

GREP_DEFAULT_CONTEXT = 2
GREP_DEFAULT_MAX_MATCHES = 100
GREP_MAX_MATCHES_HARD_CAP = 1000

HTTP_HOST = os.environ.get("QA_MCP_HOST", "127.0.0.1")
HTTP_PORT = int(os.environ.get("QA_MCP_PORT", "8765"))

QA_ROOT_REAL = os.path.realpath(QA_ROOT)


def is_inside_qa_root(path: str) -> bool:
    real = os.path.realpath(path)
    return real == QA_ROOT_REAL or real.startswith(QA_ROOT_REAL + os.sep)
