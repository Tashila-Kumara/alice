import { Button } from '@repo/ui/components/ui/button';

export default function Home() {
  return (
    <main className="flex flex-col justify-center items-center h-[calc(100vh)]">
      <section>
        <h1 className="text-8xl font-bold">Jira Teams</h1>
        <h2 className="text-center text-4xl ">A Jira Clone</h2>
      </section>
      <section className="flex gap-4 p-4">
        <Button variant="outline" className="cursor-pointer">
          Sign Up
        </Button>
        <Button className="cursor-pointer">
          Dashboard
        </Button>
      </section>
    </main>
  );
}
