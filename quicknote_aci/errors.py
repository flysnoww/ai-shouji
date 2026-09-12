class ACIError(Exception):
    code = "ACI_ERROR"
    retryable = False

    def __init__(self, message: str, *, details: dict | None = None):
        super().__init__(message)
        self.message = message
        self.details = details or {}


class ValidationError(ACIError):
    code = "ACI_INVALID_INPUT"


class UnauthorizedError(ACIError):
    code = "ACI_UNAUTHORIZED"


class NotFoundError(ACIError):
    code = "ACI_NOT_FOUND"

