/**
 * RoboCore-1 Hardware Abstraction Layer
 * Version: 1.0.0
 * 
 * Single-header HAL for RoboCore-1 RISC-V Robotics SoC
 * Include this file in your firmware to access all peripherals.
 * 
 * Usage:
 *   #define ROBOCORE_HAL_IMPLEMENTATION  // in ONE .c file only
 *   #include "robocore1_hal.h"
 * 
 * License: MIT
 */

#ifndef ROBOCORE1_HAL_H
#define ROBOCORE1_HAL_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Memory Map
 * ============================================================ */
#define RC1_BASE_PWM        0x00000000UL
#define RC1_BASE_ENC        0x00010000UL
#define RC1_BASE_PID        0x00020000UL
#define RC1_BASE_SAFETY     0x00030000UL
#define RC1_BASE_TICK       0x00040000UL
#define RC1_BASE_CAN        0x00050000UL
#define RC1_BASE_EC         0x00060000UL
#define RC1_BASE_SYS        0x00070000UL
#define RC1_BASE_DMA        0x000F0000UL

/* ============================================================
 * Register Access
 * ============================================================ */
#define RC1_REG(base, offset) (*((volatile uint32_t*)((base) + (offset))))

/* ============================================================
 * System Registers
 * ============================================================ */
#define RC1_CHIP_ID         RC1_REG(RC1_BASE_SYS, 0x00)
#define RC1_VERSION         RC1_REG(RC1_BASE_SYS, 0x04)
#define RC1_SCRATCH         RC1_REG(RC1_BASE_SYS, 0x08)
#define RC1_IRQ_ACTIVE      RC1_REG(RC1_BASE_SYS, 0x0C)
#define RC1_IRQ_MASK        RC1_REG(RC1_BASE_SYS, 0x10)
#define RC1_IRQ_CLEAR       RC1_REG(RC1_BASE_SYS, 0x14)
#define RC1_RESET_REQ       RC1_REG(RC1_BASE_SYS, 0x18)

#define RC1_CHIP_ID_EXPECTED    0xAC010002UL
#define RC1_BOOT_MARKER_GOOD    0x600DB007UL
#define RC1_BOOT_MARKER_DEAD    0xDEAD0000UL

/* IRQ bit positions */
#define RC1_IRQ_PWM_FAULT   (1 << 0)
#define RC1_IRQ_ENC_ERROR   (1 << 1)
#define RC1_IRQ_SAFE_STATE  (1 << 2)
#define RC1_IRQ_ESTOP       (1 << 3)
#define RC1_IRQ_CAN_BUSOFF  (1 << 4)
#define RC1_IRQ_CAN_RX      (1 << 5)
#define RC1_IRQ_EC_TIMEOUT  (1 << 6)
#define RC1_IRQ_EC_OP       (1 << 7)

/* ============================================================
 * PWM Engine — 16 channels, 20-bit
 * ============================================================ */
#define RC1_PWM_CH_SEL      RC1_REG(RC1_BASE_PWM, 0x00)
#define RC1_PWM_PERIOD      RC1_REG(RC1_BASE_PWM, 0x04)
#define RC1_PWM_DUTY_H      RC1_REG(RC1_BASE_PWM, 0x08)
#define RC1_PWM_DUTY_L      RC1_REG(RC1_BASE_PWM, 0x0C)
#define RC1_PWM_FAULT       RC1_REG(RC1_BASE_PWM, 0x10)
#define RC1_PWM_OUT         RC1_REG(RC1_BASE_PWM, 0x14)

#define RC1_PWM_MAX_CHANNELS    16
#define RC1_PWM_MAX_VALUE       0xFFFFFUL   /* 20-bit */

/* ============================================================
 * Encoder Interface — 16 channels, 32-bit quadrature
 * ============================================================ */
#define RC1_ENC_CH_SEL      RC1_REG(RC1_BASE_ENC, 0x00)
#define RC1_ENC_POSITION    RC1_REG(RC1_BASE_ENC, 0x04)
#define RC1_ENC_DIRECTION   RC1_REG(RC1_BASE_ENC, 0x08)
#define RC1_ENC_IDX_FLAG    RC1_REG(RC1_BASE_ENC, 0x0C)
#define RC1_ENC_CLEAR_POS   RC1_REG(RC1_BASE_ENC, 0x10)
#define RC1_ENC_CLEAR_IDX   RC1_REG(RC1_BASE_ENC, 0x14)
#define RC1_ENC_ERROR_FLAG  RC1_REG(RC1_BASE_ENC, 0x18)

#define RC1_ENC_MAX_CHANNELS    16

/* ============================================================
 * PID Controller — 8 channels, 1MHz update
 * ============================================================ */
#define RC1_PID_BASE_CH(ch) (RC1_BASE_PID + ((ch) * 0x20))
#define RC1_PID_TARGET(ch)  RC1_REG(RC1_PID_BASE_CH(ch), 0x00)
#define RC1_PID_KP(ch)      RC1_REG(RC1_PID_BASE_CH(ch), 0x04)
#define RC1_PID_KI(ch)      RC1_REG(RC1_PID_BASE_CH(ch), 0x08)
#define RC1_PID_KD(ch)      RC1_REG(RC1_PID_BASE_CH(ch), 0x0C)
#define RC1_PID_OUT_MAX(ch) RC1_REG(RC1_PID_BASE_CH(ch), 0x10)
#define RC1_PID_OUTPUT(ch)  RC1_REG(RC1_PID_BASE_CH(ch), 0x14)
#define RC1_PID_ENABLE      RC1_REG(RC1_BASE_PID, 0x100)

#define RC1_PID_MAX_CHANNELS    8

/* ============================================================
 * Safety Subsystem
 * ============================================================ */
#define RC1_SAFETY_FAULT    RC1_REG(RC1_BASE_SAFETY, 0x00)
#define RC1_SAFETY_CLEAR    RC1_REG(RC1_BASE_SAFETY, 0x04)
#define RC1_SAFETY_STATE    RC1_REG(RC1_BASE_SAFETY, 0x08)
#define RC1_SAFETY_STATUS   RC1_REG(RC1_BASE_SAFETY, 0x14)
#define RC1_WD_PET          RC1_REG(RC1_BASE_SAFETY, 0x0C)
#define RC1_WD_ENABLE       RC1_REG(RC1_BASE_SAFETY, 0x10)

/* Fault bits */
#define RC1_FAULT_ESTOP     (1 << 0)
#define RC1_FAULT_PWM       (1 << 1)
#define RC1_FAULT_ENC       (1 << 2)

/* ============================================================
 * CAN FD Controller
 * ============================================================ */
#define RC1_CAN_TX_ID       RC1_REG(RC1_BASE_CAN, 0x00)
#define RC1_CAN_TX_CTRL     RC1_REG(RC1_BASE_CAN, 0x04)
#define RC1_CAN_TX_DATA(n)  RC1_REG(RC1_BASE_CAN, 0x08 + ((n) * 4))
#define RC1_CAN_RX_ID       RC1_REG(RC1_BASE_CAN, 0x90)
#define RC1_CAN_RX_DLC      RC1_REG(RC1_BASE_CAN, 0x94)
#define RC1_CAN_RX_DATA(n)  RC1_REG(RC1_BASE_CAN, 0x98 + ((n) * 4))
#define RC1_CAN_STATUS      RC1_REG(RC1_BASE_CAN, 0xA0)

/* CAN TX ctrl bits */
#define RC1_CAN_CTRL_IDE    (1 << 29)   /* Extended ID */
#define RC1_CAN_CTRL_RTR    (1 << 30)   /* Remote frame */
#define RC1_CAN_CTRL_BRS    (1 << 31)   /* Bit rate switch */
#define RC1_CAN_CTRL_FDF    (1 << 28)   /* FD frame */
#define RC1_CAN_CTRL_VALID  (1 << 0)    /* Trigger TX */

/* CAN status bits */
#define RC1_CAN_STATUS_BUSOFF       (1 << 0)
#define RC1_CAN_STATUS_ERR_PASSIVE  (1 << 1)

#define RC1_CAN_MAX_DLC     15
#define RC1_CAN_MAX_DATA    64  /* bytes, FD mode */

/* ============================================================
 * EtherCAT MAC
 * ============================================================ */
#define RC1_EC_STATE        RC1_REG(RC1_BASE_EC, 0x00)
#define RC1_EC_LINK_OP      RC1_REG(RC1_BASE_EC, 0x04)
#define RC1_EC_WKC          RC1_REG(RC1_BASE_EC, 0x08)
#define RC1_EC_PD_ADDR      RC1_REG(RC1_BASE_EC, 0x0C)
#define RC1_EC_PD_WDATA     RC1_REG(RC1_BASE_EC, 0x10)
#define RC1_EC_PD_RDATA     RC1_REG(RC1_BASE_EC, 0x14)
#define RC1_EC_PD_CTRL      RC1_REG(RC1_BASE_EC, 0x18)

/* EtherCAT states */
#define RC1_EC_STATE_INIT   0x01
#define RC1_EC_STATE_PREOP  0x02
#define RC1_EC_STATE_SAFEOP 0x04
#define RC1_EC_STATE_OP     0x08

/* ============================================================
 * DMA Engine — 8 channels
 * ============================================================ */
#define RC1_DMA_DESC_BASE(ch, desc) \
    (RC1_BASE_DMA + ((ch) * 0x100) + ((desc) * 0x10))

#define RC1_DMA_DESC_SRC(ch, desc)  RC1_REG(RC1_DMA_DESC_BASE(ch,desc), 0x00)
#define RC1_DMA_DESC_DST(ch, desc)  RC1_REG(RC1_DMA_DESC_BASE(ch,desc), 0x04)
#define RC1_DMA_DESC_CTRL(ch, desc) RC1_REG(RC1_DMA_DESC_BASE(ch,desc), 0x08)
#define RC1_DMA_CH_ENABLE(ch)       RC1_REG(RC1_BASE_DMA + 0x800, (ch) * 4)

/* DMA descriptor ctrl bits */
#define RC1_DMA_TRIG_SW     (0 << 8)
#define RC1_DMA_TRIG_SYNC0  (1 << 8)
#define RC1_DMA_TRIG_SYNC1  (2 << 8)
#define RC1_DMA_TRIG_1KHZ   (3 << 8)
#define RC1_DMA_TRIG_1MHZ   (4 << 8)
#define RC1_DMA_TRIG_CAN_RX (5 << 8)
#define RC1_DMA_AUTO_RELOAD (1 << 14)
#define RC1_DMA_ENABLE      (1 << 15)

#define RC1_DMA_MAX_CHANNELS    8
#define RC1_DMA_MAX_DESCS       4

/* ============================================================
 * Data Types
 * ============================================================ */

/** CAN FD frame */
typedef struct {
    uint32_t id;        /* 11-bit or 29-bit */
    bool     ide;       /* Extended ID */
    bool     brs;       /* Bit rate switch */
    bool     fdf;       /* FD frame */
    uint8_t  dlc;       /* Data length code (0-15) */
    uint8_t  data[64];  /* Up to 64 bytes */
} rc1_can_frame_t;

/** DMA descriptor */
typedef struct {
    uint32_t src;       /* Source address */
    uint32_t dst;       /* Destination address */
    uint8_t  len;       /* Transfer length in words */
    uint8_t  trigger;   /* Trigger source */
    bool     auto_reload;
    bool     enable;
} rc1_dma_desc_t;

/** PID configuration */
typedef struct {
    int32_t  kp;        /* Proportional gain (Q16) */
    int32_t  ki;        /* Integral gain (Q16) */
    int32_t  kd;        /* Derivative gain (Q16) */
    int32_t  out_max;   /* Output clamp */
} rc1_pid_config_t;

/** System status */
typedef struct {
    uint32_t chip_id;
    uint32_t version;
    bool     safe_state;
    bool     estop_active;
    uint32_t fault_reg;
    uint16_t irq_active;
} rc1_status_t;

/* ============================================================
 * Return Codes
 * ============================================================ */
typedef enum {
    RC1_OK              =  0,
    RC1_ERR_CHIP_ID     = -1,   /* Wrong chip ID */
    RC1_ERR_SAFE_STATE  = -2,   /* System in safe state */
    RC1_ERR_INVALID_CH  = -3,   /* Invalid channel number */
    RC1_ERR_INVALID_ARG = -4,   /* Invalid argument */
    RC1_ERR_TIMEOUT     = -5,   /* Operation timed out */
    RC1_ERR_CAN_BUSOFF  = -6,   /* CAN bus off */
    RC1_ERR_EC_NOT_OP   = -7,   /* EtherCAT not in OP state */
} rc1_err_t;

/* ============================================================
 * Function Declarations
 * ============================================================ */

/* System */
rc1_err_t   rc1_init(void);
rc1_err_t   rc1_get_status(rc1_status_t *status);
void        rc1_irq_enable(uint16_t mask);
void        rc1_irq_disable(uint16_t mask);
void        rc1_irq_clear(uint16_t mask);
uint16_t    rc1_irq_get_active(void);

/* Watchdog */
void        rc1_wd_enable(uint8_t channels);
void        rc1_wd_pet(uint8_t channels);

/* Safety */
bool        rc1_is_safe_state(void);
bool        rc1_is_estop(void);
uint32_t    rc1_get_faults(void);
void        rc1_clear_faults(void);

/* PWM */
rc1_err_t   rc1_pwm_set(uint8_t ch, uint32_t period, uint32_t duty);
rc1_err_t   rc1_pwm_set_duty(uint8_t ch, uint32_t duty);
rc1_err_t   rc1_pwm_set_percent(uint8_t ch, float percent);
bool        rc1_pwm_fault(void);

/* Encoder */
rc1_err_t   rc1_enc_get_position(uint8_t ch, int32_t *pos);
rc1_err_t   rc1_enc_get_direction(uint8_t ch, bool *forward);
rc1_err_t   rc1_enc_clear_position(uint8_t ch);
bool        rc1_enc_index_flag(uint8_t ch);
bool        rc1_enc_error(uint8_t ch);

/* PID */
rc1_err_t   rc1_pid_configure(uint8_t ch, const rc1_pid_config_t *cfg);
rc1_err_t   rc1_pid_set_target(uint8_t ch, int32_t target);
rc1_err_t   rc1_pid_get_output(uint8_t ch, int32_t *output);
rc1_err_t   rc1_pid_enable(uint8_t ch_mask);
rc1_err_t   rc1_pid_disable(uint8_t ch_mask);

/* CAN FD */
rc1_err_t   rc1_can_send(const rc1_can_frame_t *frame);
rc1_err_t   rc1_can_send_simple(uint32_t id, const uint8_t *data, uint8_t len);
rc1_err_t   rc1_can_recv(rc1_can_frame_t *frame);
bool        rc1_can_rx_available(void);
bool        rc1_can_bus_off(void);

/* EtherCAT */
uint8_t     rc1_ec_get_state(void);
bool        rc1_ec_is_operational(void);
bool        rc1_ec_link_up(void);
rc1_err_t   rc1_ec_pd_write(uint16_t addr, uint32_t data);
rc1_err_t   rc1_ec_pd_read(uint16_t addr, uint32_t *data);

/* DMA */
rc1_err_t   rc1_dma_configure(uint8_t ch, uint8_t desc,
                               const rc1_dma_desc_t *d);
rc1_err_t   rc1_dma_enable(uint8_t ch);
rc1_err_t   rc1_dma_disable(uint8_t ch);
rc1_err_t   rc1_dma_setup_ethercat_cycle(uint8_t ch,
                                          uint32_t src, uint32_t dst,
                                          uint8_t len);

/* ============================================================
 * Implementation
 * (included only when ROBOCORE_HAL_IMPLEMENTATION is defined)
 * ============================================================ */
#ifdef ROBOCORE_HAL_IMPLEMENTATION

/* ---- System ---- */

rc1_err_t rc1_init(void) {
    if (RC1_CHIP_ID != RC1_CHIP_ID_EXPECTED)
        return RC1_ERR_CHIP_ID;
    /* Enable all 4 watchdogs */
    RC1_WD_ENABLE = 0xF;
    RC1_WD_PET    = 0xF;
    /* Clear all IRQs */
    RC1_IRQ_CLEAR = 0xFFFF;
    /* Disable all PID channels */
    RC1_PID_ENABLE = 0;
    return RC1_OK;
}

rc1_err_t rc1_get_status(rc1_status_t *s) {
    if (!s) return RC1_ERR_INVALID_ARG;
    s->chip_id      = RC1_CHIP_ID;
    s->version      = RC1_VERSION;
    s->safe_state   = (RC1_SAFETY_STATE & 1);
    s->estop_active = (RC1_SAFETY_STATUS & 2) >> 1;
    s->fault_reg    = RC1_SAFETY_FAULT;
    s->irq_active   = (uint16_t)RC1_IRQ_ACTIVE;
    return RC1_OK;
}

void rc1_irq_enable(uint16_t mask) {
    RC1_IRQ_MASK |= mask;
}

void rc1_irq_disable(uint16_t mask) {
    RC1_IRQ_MASK &= ~mask;
}

void rc1_irq_clear(uint16_t mask) {
    RC1_IRQ_CLEAR = mask;
}

uint16_t rc1_irq_get_active(void) {
    return (uint16_t)RC1_IRQ_ACTIVE;
}

/* ---- Watchdog ---- */

void rc1_wd_enable(uint8_t channels) {
    RC1_WD_ENABLE = channels & 0xF;
}

void rc1_wd_pet(uint8_t channels) {
    RC1_WD_PET = channels & 0xF;
}

/* ---- Safety ---- */

bool rc1_is_safe_state(void) {
    return (RC1_SAFETY_STATE & 1) != 0;
}

bool rc1_is_estop(void) {
    return (RC1_SAFETY_STATUS & 2) != 0;
}

uint32_t rc1_get_faults(void) {
    return RC1_SAFETY_FAULT;
}

void rc1_clear_faults(void) {
    RC1_SAFETY_CLEAR = 1;
}

/* ---- PWM ---- */

rc1_err_t rc1_pwm_set(uint8_t ch, uint32_t period, uint32_t duty) {
    if (ch >= RC1_PWM_MAX_CHANNELS)   return RC1_ERR_INVALID_CH;
    if (period > RC1_PWM_MAX_VALUE)   return RC1_ERR_INVALID_ARG;
    if (duty > period)                return RC1_ERR_INVALID_ARG;
    RC1_PWM_CH_SEL = ch;
    RC1_PWM_PERIOD = period & RC1_PWM_MAX_VALUE;
    RC1_PWM_DUTY_H = (duty >> 10) & 0x3FF;
    RC1_PWM_DUTY_L = duty & 0x3FF;
    return RC1_OK;
}

rc1_err_t rc1_pwm_set_duty(uint8_t ch, uint32_t duty) {
    if (ch >= RC1_PWM_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    RC1_PWM_CH_SEL = ch;
    RC1_PWM_DUTY_H = (duty >> 10) & 0x3FF;
    RC1_PWM_DUTY_L = duty & 0x3FF;
    return RC1_OK;
}

rc1_err_t rc1_pwm_set_percent(uint8_t ch, float percent) {
    if (ch >= RC1_PWM_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    if (percent < 0.0f || percent > 100.0f) return RC1_ERR_INVALID_ARG;
    RC1_PWM_CH_SEL = ch;
    uint32_t period = (uint32_t)RC1_PWM_PERIOD;
    uint32_t duty   = (uint32_t)(period * percent / 100.0f);
    RC1_PWM_DUTY_H  = (duty >> 10) & 0x3FF;
    RC1_PWM_DUTY_L  = duty & 0x3FF;
    return RC1_OK;
}

bool rc1_pwm_fault(void) {
    return (RC1_PWM_FAULT & 1) != 0;
}

/* ---- Encoder ---- */

rc1_err_t rc1_enc_get_position(uint8_t ch, int32_t *pos) {
    if (ch >= RC1_ENC_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    if (!pos) return RC1_ERR_INVALID_ARG;
    RC1_ENC_CH_SEL = ch;
    *pos = (int32_t)RC1_ENC_POSITION;
    return RC1_OK;
}

rc1_err_t rc1_enc_get_direction(uint8_t ch, bool *forward) {
    if (ch >= RC1_ENC_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    if (!forward) return RC1_ERR_INVALID_ARG;
    *forward = (RC1_ENC_DIRECTION >> ch) & 1;
    return RC1_OK;
}

rc1_err_t rc1_enc_clear_position(uint8_t ch) {
    if (ch >= RC1_ENC_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    RC1_ENC_CLEAR_POS = (1 << ch);
    return RC1_OK;
}

bool rc1_enc_index_flag(uint8_t ch) {
    return (RC1_ENC_IDX_FLAG >> ch) & 1;
}

bool rc1_enc_error(uint8_t ch) {
    return (RC1_ENC_ERROR_FLAG >> ch) & 1;
}

/* ---- PID ---- */

rc1_err_t rc1_pid_configure(uint8_t ch, const rc1_pid_config_t *cfg) {
    if (ch >= RC1_PID_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    if (!cfg) return RC1_ERR_INVALID_ARG;
    RC1_PID_KP(ch)      = (uint32_t)cfg->kp;
    RC1_PID_KI(ch)      = (uint32_t)cfg->ki;
    RC1_PID_KD(ch)      = (uint32_t)cfg->kd;
    RC1_PID_OUT_MAX(ch) = (uint32_t)cfg->out_max;
    return RC1_OK;
}

rc1_err_t rc1_pid_set_target(uint8_t ch, int32_t target) {
    if (ch >= RC1_PID_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    RC1_PID_TARGET(ch) = (uint32_t)target;
    return RC1_OK;
}

rc1_err_t rc1_pid_get_output(uint8_t ch, int32_t *output) {
    if (ch >= RC1_PID_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    if (!output) return RC1_ERR_INVALID_ARG;
    *output = (int32_t)RC1_PID_OUTPUT(ch);
    return RC1_OK;
}

rc1_err_t rc1_pid_enable(uint8_t ch_mask) {
    RC1_PID_ENABLE |= ch_mask;
    return RC1_OK;
}

rc1_err_t rc1_pid_disable(uint8_t ch_mask) {
    RC1_PID_ENABLE &= ~ch_mask;
    return RC1_OK;
}

/* ---- CAN FD ---- */

rc1_err_t rc1_can_send(const rc1_can_frame_t *frame) {
    if (!frame) return RC1_ERR_INVALID_ARG;
    if (rc1_can_bus_off()) return RC1_ERR_CAN_BUSOFF;
    if (frame->dlc > RC1_CAN_MAX_DLC) return RC1_ERR_INVALID_ARG;

    RC1_CAN_TX_ID = frame->id & 0x1FFFFFFF;

    uint32_t ctrl = frame->dlc & 0xF;
    if (frame->ide) ctrl |= RC1_CAN_CTRL_IDE;
    if (frame->brs) ctrl |= RC1_CAN_CTRL_BRS;
    if (frame->fdf) ctrl |= RC1_CAN_CTRL_FDF;

    /* Write data words */
    uint8_t bytes = frame->dlc <= 8 ? frame->dlc : 
                    frame->dlc == 9  ? 12 :
                    frame->dlc == 10 ? 16 :
                    frame->dlc == 11 ? 20 :
                    frame->dlc == 12 ? 24 :
                    frame->dlc == 13 ? 32 :
                    frame->dlc == 14 ? 48 : 64;

    for (uint8_t i = 0; i < (bytes + 3) / 4; i++) {
        uint32_t word = 0;
        for (uint8_t b = 0; b < 4 && (i*4+b) < bytes; b++)
            word |= ((uint32_t)frame->data[i*4+b]) << (b*8);
        RC1_CAN_TX_DATA(i) = word;
    }

    RC1_CAN_TX_CTRL = ctrl | RC1_CAN_CTRL_VALID;
    return RC1_OK;
}

rc1_err_t rc1_can_send_simple(uint32_t id, const uint8_t *data, uint8_t len) {
    rc1_can_frame_t frame = {0};
    frame.id  = id;
    frame.dlc = len > 8 ? 8 : len;
    frame.fdf = false;
    if (data)
        for (uint8_t i = 0; i < frame.dlc; i++)
            frame.data[i] = data[i];
    return rc1_can_send(&frame);
}

rc1_err_t rc1_can_recv(rc1_can_frame_t *frame) {
    if (!frame) return RC1_ERR_INVALID_ARG;
    if (!rc1_can_rx_available()) return RC1_ERR_TIMEOUT;

    frame->id  = RC1_CAN_RX_ID & 0x1FFFFFFF;
    frame->dlc = RC1_CAN_RX_DLC & 0xF;

    uint8_t bytes = frame->dlc <= 8 ? frame->dlc : 8;
    for (uint8_t i = 0; i < (bytes + 3) / 4; i++) {
        uint32_t word = RC1_CAN_RX_DATA(i);
        for (uint8_t b = 0; b < 4 && (i*4+b) < bytes; b++)
            frame->data[i*4+b] = (word >> (b*8)) & 0xFF;
    }
    rc1_irq_clear(RC1_IRQ_CAN_RX);
    return RC1_OK;
}

bool rc1_can_rx_available(void) {
    return (rc1_irq_get_active() & RC1_IRQ_CAN_RX) != 0;
}

bool rc1_can_bus_off(void) {
    return (RC1_CAN_STATUS & RC1_CAN_STATUS_BUSOFF) != 0;
}

/* ---- EtherCAT ---- */

uint8_t rc1_ec_get_state(void) {
    return (uint8_t)(RC1_EC_STATE & 0xF);
}

bool rc1_ec_is_operational(void) {
    return (RC1_EC_LINK_OP & 1) != 0;
}

bool rc1_ec_link_up(void) {
    return (RC1_EC_LINK_OP & 2) != 0;
}

rc1_err_t rc1_ec_pd_write(uint16_t addr, uint32_t data) {
    RC1_EC_PD_ADDR  = addr;
    RC1_EC_PD_WDATA = data;
    RC1_EC_PD_CTRL  = 0x1; /* write strobe */
    return RC1_OK;
}

rc1_err_t rc1_ec_pd_read(uint16_t addr, uint32_t *data) {
    if (!data) return RC1_ERR_INVALID_ARG;
    RC1_EC_PD_ADDR = addr;
    RC1_EC_PD_CTRL = 0x2; /* read strobe */
    *data = RC1_EC_PD_RDATA;
    return RC1_OK;
}

/* ---- DMA ---- */

rc1_err_t rc1_dma_configure(uint8_t ch, uint8_t desc,
                              const rc1_dma_desc_t *d) {
    if (ch >= RC1_DMA_MAX_CHANNELS)   return RC1_ERR_INVALID_CH;
    if (desc >= RC1_DMA_MAX_DESCS)    return RC1_ERR_INVALID_ARG;
    if (!d)                            return RC1_ERR_INVALID_ARG;

    RC1_DMA_DESC_SRC(ch, desc)  = d->src;
    RC1_DMA_DESC_DST(ch, desc)  = d->dst;

    uint32_t ctrl = d->len & 0xFF;
    ctrl |= (uint32_t)(d->trigger) << 8;
    if (d->auto_reload) ctrl |= RC1_DMA_AUTO_RELOAD;
    if (d->enable)      ctrl |= RC1_DMA_ENABLE;
    RC1_DMA_DESC_CTRL(ch, desc) = ctrl;
    return RC1_OK;
}

rc1_err_t rc1_dma_enable(uint8_t ch) {
    if (ch >= RC1_DMA_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    RC1_DMA_CH_ENABLE(ch) = 1;
    return RC1_OK;
}

rc1_err_t rc1_dma_disable(uint8_t ch) {
    if (ch >= RC1_DMA_MAX_CHANNELS) return RC1_ERR_INVALID_CH;
    RC1_DMA_CH_ENABLE(ch) = 0;
    return RC1_OK;
}

rc1_err_t rc1_dma_setup_ethercat_cycle(uint8_t ch,
                                        uint32_t src, uint32_t dst,
                                        uint8_t len) {
    rc1_dma_desc_t d = {
        .src         = src,
        .dst         = dst,
        .len         = len,
        .trigger     = 1,   /* SYNC0 */
        .auto_reload = true,
        .enable      = true
    };
    rc1_err_t err = rc1_dma_configure(ch, 0, &d);
    if (err != RC1_OK) return err;
    return rc1_dma_enable(ch);
}

#endif /* ROBOCORE_HAL_IMPLEMENTATION */

#ifdef __cplusplus
}
#endif

#endif /* ROBOCORE1_HAL_H */
