import { NotFoundContent } from "@/components/marketing/not-found-content";

/** Shown when a marketing route calls notFound(), such as a help article that doesn't exist. */
export default function NotFound() {
  return <NotFoundContent />;
}
