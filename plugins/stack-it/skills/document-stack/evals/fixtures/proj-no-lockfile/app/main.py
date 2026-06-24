from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlmodel import Field, Session, SQLModel, create_engine, select

engine = create_engine("sqlite:///todo.db")


class Todo(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    SQLModel.metadata.create_all(engine)
    yield


app = FastAPI(lifespan=lifespan)


@app.post("/todos", status_code=201)
def create_todo(todo: Todo) -> Todo:
    with Session(engine) as session:
        session.add(todo)
        session.commit()
        session.refresh(todo)
        return todo


@app.get("/todos")
def list_todos() -> list[Todo]:
    with Session(engine) as session:
        return list(session.exec(select(Todo)).all())
