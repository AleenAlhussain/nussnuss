CREATE TABLE "avatars" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"mime" text NOT NULL,
	"data" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "avatars_mime" CHECK ("avatars"."mime" in ('image/jpeg','image/png','image/webp'))
);
--> statement-breakpoint
ALTER TABLE "changes" ADD COLUMN "actor" uuid;--> statement-breakpoint
ALTER TABLE "groups" ADD COLUMN "cover" text;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "avatar" jsonb;--> statement-breakpoint
ALTER TABLE "users" ADD COLUMN "activity_seen_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "avatars" ADD CONSTRAINT "avatars_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "avatars_user_idx" ON "avatars" USING btree ("user_id");--> statement-breakpoint
ALTER TABLE "changes" ADD CONSTRAINT "changes_actor_users_id_fk" FOREIGN KEY ("actor") REFERENCES "public"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "changes_group_at_idx" ON "changes" USING btree ("group_id","at");