import { useForm } from "react-hook-form";

type Fields = { name: string; email: string };

export function ContactForm() {
  const { register, handleSubmit, formState: { errors } } = useForm<Fields>();
  return (
    <form onSubmit={handleSubmit(() => {})} className="mx-auto max-w-md space-y-4 p-6">
      <input className="w-full rounded border px-3 py-2" placeholder="Name"
        {...register("name", { required: "Name is required" })} />
      {errors.name && <p className="text-sm text-red-600">{errors.name.message}</p>}
      <button className="rounded bg-blue-600 px-4 py-2 text-white" type="submit">Send</button>
    </form>
  );
}
