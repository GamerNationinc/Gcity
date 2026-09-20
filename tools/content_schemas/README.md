# Content schemas

One `<kind>.json` per content kind. The presence of the file registers the kind with
`tools/validate_content.py`; the first kind (weapon frames and parts) arrives with M1,
and its schema-checking logic lands in the validator in the same commit.
