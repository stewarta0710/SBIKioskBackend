from pydantic import BaseModel, EmailStr, Field, field_validator


class VisitorSubmission(BaseModel):
    """Payload from the kiosk browser. Server adds visitor_name and received_at."""

    visitor_first_name: str = Field(..., min_length=1, max_length=100)
    visitor_last_name: str = Field(..., min_length=1, max_length=100)
    company: str = Field("", max_length=200)
    phone: str = Field(..., min_length=7, max_length=40)
    email: EmailStr
    host_name: str = Field(..., min_length=1, max_length=200)
    visit_purpose: str = Field("", max_length=500)
    email_contact_permission: bool = False
    us_citizen_or_national: bool

    @field_validator("visitor_first_name", "visitor_last_name", mode="before")
    @classmethod
    def strip_names(cls, v: object) -> object:
        if isinstance(v, str):
            return v.strip()
        return v
