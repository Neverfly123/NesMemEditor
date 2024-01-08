.segment "HEADER"
	.byte "NES"		;identification string
	.byte $1A
	.byte $02		;amount of PRG ROM in 16K units
	.byte $01		;amount of CHR ROM in 8K units
	.byte $00		;mapper and mirroing
	.byte $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00

.segment "ZEROPAGE"
nmi_lock:       .res 1 ; prevents NMI re-entry
nmi_count:      .res 1 ; is incremented every NMI
nmi_ready:      .res 1 ; set to 1 to push a PPU frame update, 2 to turn rendering off next NMI
PPUattribute: 	.res 1 ; STORE THE ATTRIBUTE VALUE FOR (4*4) *ALL
cursor_x:       .res 1 ; x cursor position
cursor_y:       .res 1 ; y cursor position
cursor_BgPos:	.res 2 ; cursor line position in background, used for update background character
getKey:         .res 1 ; keyinput ascii code
LastKey:		.res 1 ; Last Keyboard Input
nmtBuffer_add:	.RES 2 ; name table buffer POINTER
PPU_nmtAdd:		.RES 2 ; PPU nametable address
nmtUpdateCount:	.res 1 ; count howmany times nametable undated,after 16 times it go from 0 sine each time update 64byte.
MemView_Start:	.res 2 ; address for mem viewer start to show
MemView_End:	.res 2 ; address for mem viewer end
BinaryVonMem:	.res 1 ; temperiory variable for convert binary value from memory to screen
Gamepad: 		.res 1
Lastgamepad: 	.res 1
.segment "BSS"
nmtBuffer: .res 960 ; nametable update entry buffer for PPU update

.segment "STARTUP"
RESET:
	SEI 		;disables interupts
	CLD			;turn off decimal mode
	LDX #%1000000	;disable sound IRQ
	STX $4017
	LDX #$00
	STX $4010		;disable PCM
	
;initialize the stack register
	LDX #$FF
	TXS 		;transfer x to the stack
	
; Clear PPU registers
	LDX #$00
	STX $2000
	STX $2001

;WAIT FOR VBLANK
:
	BIT $2002
	BPL :-

;CLEARING 2K MEMORY
	TXA
CLEARMEMORY:
	STA $0000, X	;$0000 - $07FF
	STA $0100, X
	STA $0300, X
	STA $0400, X
	STA $0500, X
	STA $0600, X
	STA $0700, X
	sta $6000, x	;SRAM FOR PPU buffer
	sta $6100, x
	sta $6200, x
	sta $6300, x
		LDA #$FF
		STA $0200, X
		LDA #$00
	INX
	BNE CLEARMEMORY

initialize_cursor:
	lda #$05
	sta cursor_y
	lda #$00
	sta cursor_x
	lda #$0d
	sta getKey
	lda #$08
	sta Gamepad

;initialize nametable BUFFER POINTER
	lda #<nmtBuffer
	sta nmtBuffer_add
	lda #>nmtBuffer
	sta nmtBuffer_add+1
	lda #$20
	sta PPU_nmtAdd+1
	
	ldx #$00
	
LOADBACKGROUNDP1:
	LDA BACKGROUNDDATA, X
	STA nmtBuffer, x
	INX
	BNE LOADBACKGROUNDP1
;update PPU attribute
	lda #0
	sta PPUattribute

;WAIT FOR VBLANK
:
	BIT $2002
	BPL :-
	
;SETTING SPRITE RANGE
	LDA #$02
	STA $4014
	NOP
	
;LOADPALETTES
	LDA #$3F	;$3F00
	STA $2006
	LDA #$00
	STA $2006	
	LDX #$00
	
LOADPALETTES:
	LDA PALETTEDATA, X
	STA $2007
	INX
	CPX #$20
	BNE LOADPALETTES

;LOAD BACKGROUND PALETTEDATA
	LDA #$23	;$23C0
	STA $2006
	LDA #$C0
	STA $2006
	LDX #$00
	LDA $00
	
LOADBACKGROUNDPALETTEDATA:
	STA $2007
	INX
	CPX #$40
	BNE LOADBACKGROUNDPALETTEDATA

;RESET SCROLL
	LDA #$00
	STA $2005
	STA $2005
	
;show sprites and background
	LDA #%00011110
	STA $2001

;WAIT FOR VBLANK
:
	BIT $2002
	BPL :-

;ENABLE INTERUPTS	
	LDA #%10000000
	STA $2000			;WHEN VBLANK OCCURS CALL NMI	
	CLI

INFLOOP:
;scan Keyboard
	jsr	ScanKey
	cmp #0
	beq @Skip_KeyInput
	LDX LastKey
	cpx #0
	BEQ :+
	cmp LastKey
	beq @Skip_KeyInput
	:
;keyinput Display on screen
	and #%01100000	;see if it is printable characters
	beq :+
	JSR CursorInBackground
	ldy cursor_x
	lda getKey
	sta (cursor_BgPos),Y
	jsr CursorShift_Hex
	jmp @Skip_KeyInput
	:
	lda getKey
	CMP #$0D		;keyboard return input
	BNE :+
	lda cursor_y
	cmp #7			;check see if cursor at last input line
	beq @StartHexViewer
	JSR KbReturn_hex
	jmp @Skip_KeyInput
@StartHexViewer:
	jsr HexViewerCode
	:
	cmp #$08		;keyboard del Input
	BNE @Skip_KeyInput
	jsr KbDel_Hex
@Skip_KeyInput:

; read Gamepad
	jsr gamepad_poll
	cmp #0
	beq @Skip_GamePad
	LDX Lastgamepad
	cpx #0
	BEQ :+
	cmp Lastgamepad
	beq @Skip_GamePad
	:
	; respond to Gamepad state
	lda Gamepad
	and #PAD_START
	beq :+
		jsr HexViewerCode ; start trumps everything, dont check other buttons
	:
	lda Gamepad
	and #PAD_U
	beq :+
		jsr push_u
	:
	lda Gamepad
	and #PAD_D
	beq :+
		jsr push_d
	:
	lda Gamepad
	and #PAD_L
	beq :+
		jsr push_l
	:
	lda Gamepad
	and #PAD_R
	beq :+
		jsr push_r
	:
	lda Gamepad
	and #PAD_SELECT
	beq :+
		jsr push_select
	:
	lda Gamepad
	and #PAD_B
	beq :+
		jsr push_b
	:
	lda Gamepad
	and #PAD_A
	beq @Skip_GamePad
		jsr push_a
@Skip_GamePad:

; ready for ppu update
	jsr ppu_update
@LoopEnd:
	JMP INFLOOP
	
;FOLLOWING CODE ARE SUB RUTINES------------------------------------------------------
	;Control Pad
	PAD_A      = $01
	PAD_B      = $02
	PAD_SELECT = $04
	PAD_START  = $08
	PAD_U      = $10
	PAD_D      = $20
	PAD_L      = $40
	PAD_R      = $80

	; gamepad_poll: this reads the Gamepad state into the variable labelled "Gamepad"
	;   This only reads the first Gamepad, and also if DPCM samples are played they can
	;   conflict with Gamepad reading, which may give incorrect results.
	gamepad_poll:
		lda Gamepad
		sta Lastgamepad
		; strobe the Gamepad to latch current button state
		lda #1
		sta $4016
		lda #0
		sta $4016
		; read 8 bytes from the interface at $4016
		ldx #8
		:
			pha
			lda $4016
			; combine low two bits and store in carry bit
			and #%00000011
			cmp #%00000001
			pla
			; rotate carry into Gamepad variable
			ror
			dex
			bne :-
		sta Gamepad
		rts

	push_u:
		jsr CursorInBackground
		ldy cursor_x
		lda (cursor_BgPos), Y
		tax
		INX
		TXA
		and #%00001111
		ora #%01100000
		sta (cursor_BgPos), Y
		rts
	push_d:
		jsr CursorInBackground
		ldy cursor_x
		lda (cursor_BgPos), Y
		tax
		deX
		TXA
		and #%00001111
		ora #%01100000
		sta (cursor_BgPos), Y
		rts	
	push_l:
		jmp CursorShiftL_Hex
	push_r:
		jmp CursorShift_Hex
	push_a:
		lda cursor_y
		cmp #7			;check see if cursor at last input line
		BNE :+
		jmp HexViewerCode
		:
		jmp KbReturn_hex
	push_b:	
		JSR CursorInBackground
		ldy cursor_x
		lda #0
		sta (cursor_BgPos), Y
		rts
	push_select:
		lda cursor_y
		cmp #5
		beq :+
		lda #5
		sta cursor_y
		rts
		:
		lda #7
		sta cursor_y
		rts
		
	; ScanKeyboard
	ScanKey:
		lda getKey
		sta LastKey
		ldx #$00
		lda #$05
		sta $4016	;reset to row 0, column 0
	@LoopCol:
		lda #$04
		sta $4016	;select column 0, next row if not just reset
		lda $4017
		EOR #$FF
		AND #%00011110
		bne @ColumnDecode
		INX
	;LoopCol1:
		lda #$06
		sta $4016	;select column 1, next row if not just reset
		lda $4017
		EOR #$FF
		AND #%00011110
		bne @ColumnDecode
		INX
		cpx #$12
		bne @LoopCol
		lda #$00
		sta getKey
		jmp @ScanKeyEnd
	@ColumnDecode:
		lsr A
		lsr A
		cmp #$4
		BNE :+
		lda #$3		;CONVERT COLUMN BIT INTO COLUMN NUMBER TO MATCH THE KeyboardMartix
		:
		sta getKey
		txa
		asl
		asl			;CONVERT ROW NUMBER INTO THE 3RD BIT OF KeyboardMartix
		ora getKey	;NOW INPUT BIT CAN MATCH THE KeyboardMartixs address
		tax
		lda KeyboardMartix_Hex, x	;this is for hex mode
		sta getKey
	@ScanKeyEnd:
		rts
		
	CursorInBackground:		;get current cursor line address in background
		LDA #0
		STA cursor_BgPos+1
		lda cursor_y
		CLC
		asl
		rol cursor_BgPos+1
		asl 
		rol cursor_BgPos+1
		asl
		rol cursor_BgPos+1
		asl
		rol cursor_BgPos+1
		asl
		rol cursor_BgPos+1
		sta cursor_BgPos
		lda #<nmtBuffer
		adc cursor_BgPos
		sta cursor_BgPos
		lda #>nmtBuffer
		adc cursor_BgPos+1
		sta cursor_BgPos+1
		rts

	CursorShift:
		ldy cursor_x
		CPY #31
		BNE :+
		jsr KbReturn
		JMP @EndCursorShift
		:
		inc cursor_x
	@EndCursorShift:
		rts
	
	CursorShift_Hex:
		ldy cursor_x
		CPY #3
		BNE :+
		jsr KbReturn_hex
		JMP @EndCursorShiftHex
		:
		inc cursor_x
	@EndCursorShiftHex:
		rts
	
	CursorShiftL:		;shift cursor to left
		ldy cursor_x
		CPY #0
		BNE :+
		lda #31
		sta cursor_x
		dec cursor_y
		lda cursor_y
		cmp #0
		bne @EndCursorShiftL
		sta cursor_x
		lda #1
		sta cursor_y
		JMP @EndCursorShiftL
		:
		dec cursor_x
	@EndCursorShiftL:
		rts

	CursorShiftL_Hex:		;shift cursor to left for memory viewer
		ldx cursor_x
		CPx #0
		BNE :+
		lda #3
		sta cursor_x
		lda #5
		sta cursor_y
		JMP @EndCursorShiftLHex
		:
		dec cursor_x
	@EndCursorShiftLHex:
		rts

	KbReturn:
		LDA #0
		STA cursor_x
		inc cursor_y
		lda cursor_y
		cmp #29
		bne @KbReturnEnd
		lda #1
		sta cursor_y
	@KbReturnEnd:
		rts
		
	KbReturn_hex:
		LDA #0
		STA cursor_x
		lda #7
		sta cursor_y
	@KbReturnHexEnd:
		rts
		
	KbDel:
		jsr CursorShiftL
		JSR CursorInBackground
		ldy cursor_x
		lda #0
		sta (cursor_BgPos), Y
	@KbDelEnd:
		rts

	KbDel_Hex:		;for memory viewer
		jsr CursorShiftL_Hex
		JSR CursorInBackground
		ldy cursor_x
		lda #0
		sta (cursor_BgPos), Y
	@KbDelHexEnd:
		rts

	HexViewerCode:
		lda #$CC
		sta PPUattribute
	;Change BACKGROUND PALETTEDATA
		LDA #$23	;$23C0
		STA $2006
		LDA #$C0
		STA $2006
		LDX #$CC
		LDA $00
	;calculate low bit of start address
		lda nmtBuffer+163	;low bit of low byte start address
		and #%00001111
		sta MemView_Start
		lda nmtBuffer+162	;high bit of low byte start address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_Start
		sta MemView_Start	
	;calculate high bit of start address
		lda nmtBuffer+161	;low bit of high byte start address
		and #%00001111
		sta MemView_Start+1
		lda nmtBuffer+160	;high bit of high byte start address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_Start+1
		sta MemView_Start+1
	;calculate low bit of end address
		lda nmtBuffer+227	;low bit of low byte end address
		and #%00001111
		sta MemView_End
		lda nmtBuffer+226	;high bit of low byte end address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_End
		sta MemView_End
	;calculate high bit of end address
		lda nmtBuffer+225	;low bit of high byte end address
		and #%00001111
		sta MemView_End+1
		lda nmtBuffer+224	;high bit of high byte end address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_End+1
		sta MemView_End+1
		sec
		lda MemView_End
		sbc MemView_Start
		LDA MemView_End+1
		sbc MemView_Start+1
		BCS :+
		jmp @HexViewerEnd	;IF START ADDRESS GREATER THAN END ADDRESS, RESET PROGRAM
		:
		jsr SetBackgroundBlack
		
	;SET CURSOR POSITION AT TOP LEFT OF THE SCREEN
		LDA #0
		STA cursor_x
		LDA #1
		STA cursor_y
		
	;DISPLAY MEMORY ADDRESS ON SCREEN	
	@NewSubPage:
		JSR CursorInBackground
		;DISPLAY high byte
		LDY #0
		LDA MemView_Start+1 
		JSR BIN_HEX_HighBIT
		STA (cursor_BgPos), Y	;STORE THE HEXDEC CODE TO PPU buffer
		INY
		LDA MemView_Start+1 
		JSR BIN_HEX_LowBIT
		STA (cursor_BgPos), Y	;STORE THE HEXDEC CODE TO PPU buffer
		INY
		;DISPLAY low byte
		LDA MemView_Start
		jsr BIN_HEX_HighBIT
		STA (cursor_BgPos), Y	;STORE THE HEXDEC CODE TO PPU buffer
		INY
		LDA MemView_Start
		JSR BIN_HEX_LowBIT
		STA (cursor_BgPos), Y	;STORE THE HEXDEC CODE TO PPU buffer
		INC cursor_y
		;DISPLAY a line of 16 BYTEs IN SELECTED MEMORY sub PAGE
		JSR CursorInBackground
		LDX MemView_Start
		LDY #0
		:
		LDA (MemView_Start), Y
		sta BinaryVonMem
		tya
		pha
		ASL
		tay
		lda BinaryVonMem
		JSR BIN_HEX_HighBIT
		STA (cursor_BgPos), Y
		iny
		lda BinaryVonMem
		jsr BIN_HEX_LowBIT
		STA (cursor_BgPos), Y
		pla
		tay
		INY
		INX
		TXA		;check for PPU update every 2 lines Input
		and #%00001111
		BNE :-
		;check if reach the end of the inputed memory address
		inc cursor_y
		lda cursor_y
		cmp #29
		BNE @Skip_KeyInput
		lda #1
		sta cursor_y
		jsr KeyInToContinue
		jsr SetBackgroundBlack
		@Skip_KeyInput:
		LDA MemView_Start		;if reachs 16 byte means current line is full, new line needed
		and #%11110000
		CLC
		adc #$10
		sta MemView_Start
		lda #0
		adc MemView_Start+1
		sta MemView_Start+1
		;Check for end
		sec
		lda MemView_End
		sbc MemView_Start
		LDA MemView_End+1
		sbc MemView_Start+1
		BCC @HexViewerEnd
		jmp @NewSubPage
	@HexViewerEnd:
		jsr KeyInToContinue
		jmp RESET
		
	KeyInToContinue:		;wait enter key to turn screen to next page
		jsr ppu_update
		jsr gamepad_poll
		jsr	ScanKey
		ora Gamepad
		beq KeyInToContinue
		LDa LastKey
		ora Lastgamepad
		BEQ :+
		lda getKey
		cmp LastKey
		beq KeyInToContinue
		lda Gamepad
		cmp Lastgamepad
		beq KeyInToContinue
		:
		lda getKey
		CMP #$0D			;keyboard return input
		beq @EndWait
		lda Gamepad
		CMP #PAD_D
		beq @EndWait
		CMP #PAD_START
		beq @EndProgram
		Jmp KeyInToContinue
	@EndWait:
		rts
	@EndProgram:
		jmp RESET
		
	BIN_HEX_HighBIT:		;convert hexdecimal to readable character
		AND #%11110000
		lsr
		lsr
		lsr
		lsr
		ORA #%01100000		;FORM THE CODE CAN MATCH THE KeyboardMartix_Hex FOR THE LEFT 4 BIT BINARY
		rts
		
	BIN_HEX_LowBIT:			;convert hexdecimal to readable character
		AND #%00001111
		ORA #%01100000		;FORM THE CODE CAN MATCH THE KeyboardMartix_Hex FOR THE right 4 BIT BINARY
		rts
	
	SetBackgroundBlack:
		ldx #0
	@LOADBACKGROUND:
		LDA #0
		STA nmtBuffer, x
		STA nmtBuffer+256, x
		STA nmtBuffer+512, x
		INX
		BNE @LOADBACKGROUND
	@LOADBACKGROUNDP4:
		STA nmtBuffer+768, x
		INX
		CPX #$C0
		BNE @LOADBACKGROUNDP4
		rts
	

	UpdateBackgroundAdd:	;calculate the nametable buffer address for name table update during VBLANK, each time update 64byte.
		ldx nmtUpdateCount
		cpx #15
		beq @zeroAdd
		lda PPU_nmtAdd	;update PPU nametable address;
		CLC
		adc #64
		sta PPU_nmtAdd
		lda #$00
		adc PPU_nmtAdd+1
		sta PPU_nmtAdd+1
		lda nmtBuffer_add	;update MEMORY nametable address;
		CLC
		adc #64
		sta nmtBuffer_add
		lda #$00
		adc nmtBuffer_add+1
		sta nmtBuffer_add+1
		inc nmtUpdateCount
		jmp @endAddUpdate
	@zeroAdd:				;nametable address set to $00
		lda #$00
		sta nmtUpdateCount
		sta PPU_nmtAdd
		lda #$20
		sta PPU_nmtAdd+1
		lda #>nmtBuffer
		sta nmtBuffer_add+1
		lda #<nmtBuffer
		sta nmtBuffer_add
	@endAddUpdate:
		rts

	ppu_update:
		lda #1
		sta nmi_ready
		:
			lda nmi_ready
			bne :-
		rts

NMI:
; save registers
	pha
	txa
	pha
	tya
	pha
; prevent NMI re-entry
	lda nmi_lock
	beq :+
		jmp @nmi_end
	:
	lda #1
	sta nmi_lock
; increment frame counter
	inc nmi_count
; decide whether enter ppu undate or not
	lda nmi_ready
	bne :+ ; nmi_ready == 0 not ready to update PPU
		jmp @ppu_update_end
	:
	
;cursor blink function
	lda nmi_count
	and #%00100000
	beq :+
		lda #$FF
		pha
		jmp @REFRESHCURSOR
	:
	lda cursor_y
	asl
	asl
	asl
	pha
@REFRESHCURSOR:		;refresh cursor
	LDA #$00
	STA $2003
	pla
	STA $2004	;Y
	LDA #$FF
	STA $2004	;CURSOR character ADDRESS
	LDA #$00
	STA $2004	;attributes
	LDA cursor_x
	clc
	asl
	asl
	asl
	STA $2004	;X	

	jsr UpdateBackgroundAdd
;updateBACKGROUND
	LDY #$00
	LDA $2002		;read PPU status to reset high/low latch
	LDA PPU_nmtAdd+1
	STA $2006
	LDA PPU_nmtAdd
	STA $2006
@UpdtBackGround:
	LDA (nmtBuffer_add), Y
	STA $2007
	INY
	cpy #64
	BNE @UpdtBackGround
; set all attributes to 0
	lda #$23
	sta $2006
	lda #$C0
	sta $2006
	lda PPUattribute
	ldx #64 ; 64 bytes
	:
		sta $2007
		dex
		bne :-
	LDA #%10000000
	STA $2000
	LDA #$00
	STA $2005
	STA $2005
	
; flag PPU update complete
	ldx #0
	stx nmi_ready
@ppu_update_end:
	; unlock re-entry flag
	lda #0
	sta nmi_lock
@nmi_end:
	; restore registers and return
	pla
	tay
	pla
	tax
	pla
	rti

PALETTEDATA:
	.byte $0E, $30, $00, $10, 	$00, $0A, $15, $01, 	$00, $29, $28, $27, 	$00, $34, $24, $14 	;background palettes
	.byte $0E, $30, $15, $30, 	$00, $0F, $11, $30, 	$00, $0F, $30, $27, 	$00, $3C, $2C, $1C 	;sprite palettes

BACKGROUNDDATA:	;32*30 BYTES
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $4E,$45,$53,$20,$4D,$45,$4D,$4F,$52,$59,$20,$56,$49,$45,$57,$45,$52,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $49,$4E,$50,$55,$54,$20,$4D,$45,$4D,$4F,$52,$59,$20,$41,$44,$44,$52,$45,$53,$53,$20,$49,$4E,$20,$48,$45,$58,$20,$44,$45,$43,$00
	.byte $52,$41,$4E,$47,$45,$20,$42,$45,$54,$57,$45,$45,$4E,$20,$30,$30,$30,$30,$20,$2D,$20,$46,$46,$46,$46,$00,$00,$00,$00,$00,$00,$00
	.byte $53,$54,$41,$52,$54,$20,$41,$44,$44,$52,$45,$53,$53,$3A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $45,$4E,$44,$20,$41,$44,$44,$52,$45,$53,$53,$3A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

KeyboardMartix_Hex:
;Col   $01,$02,$03,$04 
.byte  $00,$0d,$00,$00 ;Row0,Col0
.byte  $00,$00,$66,$00 ;Row0,Col1
.byte  $00,$00,$00,$00 ;Row1,Col0
.byte  $00,$00,$00,$00 ;Row1,Col1
.byte  $00,$00,$00,$00 ;Row2,Col0
.byte  $00,$00,$00,$60 ;Row2,Col1
.byte  $00,$00,$00,$00 ;Row3,Col0
.byte  $00,$00,$69,$68 ;Row3,Col1
.byte  $00,$00,$00,$00 ;Row4,Col0
.byte  $6b,$00,$67,$66 ;Row4,Col1
.byte  $00,$00,$00,$6d ;Row5,Col0
.byte  $6f,$6c,$65,$64 ;Row5,Col1
.byte  $00,$00,$00,$6a ;Row6,Col0
.byte  $00,$00,$6e,$63 ;Row6,Col1
.byte  $00,$00,$00,$00 ;Row7,Col0
.byte  $00,$00,$61,$62 ;Row7,Col1
.byte  $00,$00,$00,$00 ;Row8,Col0
.byte  $00,$00,$08,$00 ;Row8,Col1
	
KeyboardMartix:
;Col   $01,$02,$03,$04 
.byte  $00,$0d,$5b,$5d ;Row0,Col0
.byte  $00,$00,$36,$18 ;Row0,Col1
.byte  $00,$40,$3a,$3b ;Row1,Col0
.byte  $5f,$2f,$2d,$5e ;Row1,Col1
.byte  $00,$4f,$4c,$4b ;Row2,Col0
.byte  $2e,$2c,$50,$30 ;Row2,Col1
.byte  $00,$49,$55,$4a ;Row3,Col0
.byte  $4d,$4e,$39,$38 ;Row3,Col1
.byte  $00,$59,$47,$48 ;Row4,Col0
.byte  $42,$56,$37,$36 ;Row4,Col1
.byte  $00,$54,$52,$44 ;Row5,Col0
.byte  $46,$43,$35,$34 ;Row5,Col1
.byte  $00,$57,$53,$41 ;Row6,Col0
.byte  $58,$5a,$45,$33 ;Row6,Col1
.byte  $00,$1B,$51,$00 ;Row7,Col0
.byte  $00,$00,$31,$32 ;Row7,Col1
.byte  $02,$00,$00,$00 ;Row8,Col0
.byte  $00,$20,$08,$00 ;Row8,Col1
.segment "VECTORS"
	.word NMI
	.word RESET
	
.segment "CHARS"
	.incbin "character.chr"