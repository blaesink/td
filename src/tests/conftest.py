import pytest
from td import Todo


@pytest.fixture
def fake_todo_file():
    return """- Make bread
    - Get a haircut +Personal +Wedding"""


@pytest.fixture
def fake_todo_list() -> list[Todo]:
    return [Todo("Fix car +Roadtrip"), Todo("File taxes")]
