package app.zelefin.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SiloAvatarsTest {
    @Test
    fun identiconBatchZeroMatchesSiloWeb() {
        val batch = SiloAvatarPresets.batch(SiloAvatarStyle.Identicon, 0)
        assertEquals(18, batch.size)
        val first = batch.first()
        assertEquals("pepper-pebble", first.seed)
        assertEquals("dicebear:identicon:pepper-pebble", first.id)
        assertEquals("Pepper Pebble", first.label)
        assertEquals(
            "https://api.dicebear.com/9.x/identicon/png?seed=pepper-pebble&size=256&radius=24&backgroundType=gradientLinear",
            first.previewUrl,
        )
        assertEquals("pocket-panther", batch[1].seed)
    }

    @Test
    fun batchesDependOnStyleAndBatchNumber() {
        assertEquals("fizzy-pebble", SiloAvatarPresets.batch(SiloAvatarStyle.Robots, 2).first().seed)
        assertNotEquals(SiloAvatarPresets.batch(SiloAvatarStyle.Identicon, 0), SiloAvatarPresets.batch(SiloAvatarStyle.Identicon, 1))
        val emoji = SiloAvatarPresets.batch(SiloAvatarStyle.Emoji, 3)
        assertTrue(emoji.all { it.id.startsWith("dicebear:fun-emoji:") })
        assertTrue(emoji.all { it.previewUrl.startsWith("https://api.dicebear.com/9.x/fun-emoji/png?seed=${it.seed}&") })
        assertEquals(listOf("identicon", "initials", "bottts-neutral", "fun-emoji", "pixel-art-neutral"), SiloAvatarStyle.entries.map { it.id })
        assertEquals(listOf("Identicon", "Initials", "Robots", "Emoji", "Pixel"), SiloAvatarStyle.entries.map { it.title })
    }

    @Test
    fun readsTheSelectedPreset() {
        val selected = SiloAvatarPresets.selectedId("preset:dicebear:fun-emoji:mango-otter")
        assertEquals("dicebear:fun-emoji:mango-otter", selected)
        assertEquals(SiloAvatarStyle.Emoji, SiloAvatarPresets.style(selected))
        assertEquals("avatar-3", SiloAvatarPresets.selectedId("avatar-3"))
        assertNull(SiloAvatarPresets.style("avatar-3"))
        assertNull(SiloAvatarPresets.style("dicebear:unknown:seed"))
        assertNull(SiloAvatarPresets.selectedId(""))
        assertNull(SiloAvatarPresets.selectedId(null))
    }

    @Test
    fun patchBodySetsOrClearsThePreset() {
        assertEquals("""{"avatar":"preset:dicebear:identicon:pepper-pebble"}""", SiloAvatarPresets.patchBody("dicebear:identicon:pepper-pebble"))
        assertEquals("""{"avatar":null}""", SiloAvatarPresets.patchBody(null))
    }

    @Test
    fun rewritesSvgAvatarsToPng() {
        assertEquals(
            "https://api.dicebear.com/9.x/fun-emoji/png?seed=mango-otter&size=128&radius=24&backgroundType=gradientLinear",
            SiloAvatarUrl.displayable("https://api.dicebear.com/9.x/fun-emoji/svg?seed=mango-otter&size=128&radius=24&backgroundType=gradientLinear"),
        )
        assertEquals(
            "https://silo.example.com/profile-avatars/avatar-3.png",
            SiloAvatarUrl.displayable("https://silo.example.com/profile-avatars/avatar-3.svg"),
        )
        assertEquals("http://10.0.0.2:8080/a/b.png?x=1", SiloAvatarUrl.displayable("http://10.0.0.2:8080/a/b.SVG?x=1"))
    }

    @Test
    fun leavesOtherAvatarsAlone() {
        val upload = "https://silo.example.com/avatars/uploads/1.jpg?v=2"
        assertEquals(upload, SiloAvatarUrl.displayable(upload))
        assertEquals("https://other.example.com/9.x/x/svg", SiloAvatarUrl.displayable("https://other.example.com/9.x/x/svg"))
        assertEquals("not a url", SiloAvatarUrl.displayable("not a url"))
    }

    @Test
    fun profileAvatarsResolveToPng() {
        val text = """
            {"items":[
              {"id":"1","name":"A","avatar":"preset:dicebear:fun-emoji:mango-otter","avatar_source":"preset",
               "avatar_url":"https://api.dicebear.com/9.x/fun-emoji/svg?seed=mango-otter&size=128"},
              {"id":"2","name":"B","avatar":"preset:avatar-1","avatar_source":"preset","avatar_url":"/profile-avatars/avatar-1.svg"},
              {"id":"3","name":"C","avatar":"","avatar_source":"upload","avatar_url":"/avatars/uploads/3.jpg"}
            ],"avatar_upload_enabled":false}
        """.trimIndent()
        val profiles = SiloJson.profiles(text, "https://silo.example.com")!!.items
        assertEquals("https://api.dicebear.com/9.x/fun-emoji/png?seed=mango-otter&size=128", profiles[0].avatarUrl)
        assertEquals("preset:dicebear:fun-emoji:mango-otter", profiles[0].avatar)
        assertEquals("preset", profiles[0].avatarSource)
        assertEquals("https://silo.example.com/profile-avatars/avatar-1.png", profiles[1].avatarUrl)
        assertEquals("https://silo.example.com/avatars/uploads/3.jpg", profiles[2].avatarUrl)
        assertEquals("upload", profiles[2].avatarSource)
    }

    @Test
    fun savedLinkCarriesTheAvatarReference() {
        val link = SiloLink(
            nativeUrl = "https://silo.example.com",
            refreshToken = "r",
            accountId = "1",
            accountName = "a",
            profileId = "2",
            profileName = "Kids",
            profileAvatarUrl = "https://api.dicebear.com/9.x/identicon/svg?seed=x",
        )
        assertEquals("https://api.dicebear.com/9.x/identicon/png?seed=x", link.profile.avatarUrl)
        val updated = link.withProfile(SiloProfile("2", "Kids", avatarUrl = null, avatar = "preset:dicebear:initials:x", avatarSource = "preset"))
        assertEquals("preset:dicebear:initials:x", updated.profileAvatar)
        assertEquals("preset", updated.profileAvatarSource)
        assertEquals("preset", updated.profile.avatarSource)
    }
}
