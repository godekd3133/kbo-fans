from fastapi import HTTPException, status


def raise_not_implemented(message: str) -> None:
    raise HTTPException(status_code=status.HTTP_501_NOT_IMPLEMENTED, detail=message)
