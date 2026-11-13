import MagicLinkForm from "./MagicLinkForm";

export const dynamic = "force-dynamic";

const errors: Record<string, string> = {
  invalid: "That code is not valid or it has expired.",
  rate: "Too many tries. Wait a few minutes.",
  again: "That code was used but sign-in did not finish. Create another code on your phone.",
  unavailable: "Sign-in codes are not available on this server yet.",
};

export default function LoginPage({
  searchParams,
}: {
  searchParams?: { error?: string };
}) {
  const message = typeof searchParams?.error === "string" ? errors[searchParams.error] : undefined;

  return (
    <section className="max-w-sm">
      <h1 className="text-2xl font-semibold mb-4">Log in</h1>
      <MagicLinkForm />

      <h2 className="text-xl font-semibold mt-10 mb-2">Have a code?</h2>
      <p className="text-base mb-4">
        On your phone, open Account and tap Sign in another device. Type that code here.
        It works once, for 10 minutes.
      </p>
      {message && (
        <p className="border-2 border-[color:var(--ink)] px-4 py-3 mb-4 text-base">{message}</p>
      )}
      <form method="post" action="/auth/code" className="space-y-3">
        <label htmlFor="device-code" className="block text-base">
          Code
        </label>
        <input
          id="device-code"
          name="code"
          required
          autoCapitalize="characters"
          autoCorrect="off"
          spellCheck={false}
          autoComplete="one-time-code"
          inputMode="text"
          className="w-full border-2 border-[color:var(--ink)] bg-white px-4 py-4 text-2xl tracking-widest"
        />
        <button
          type="submit"
          className="w-full border-2 border-[color:var(--ink)] bg-[color:var(--ink)] text-white px-4 py-4 text-lg"
        >
          Sign in with code
        </button>
      </form>
    </section>
  );
}
